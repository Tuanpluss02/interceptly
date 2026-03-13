import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../storage/inspector_session.dart';
import '../trigger/inspector_trigger.dart';
import '../trigger/netspecter_config.dart';
import '../trigger/shake_detector.dart';
import 'draggable_fab.dart';
import '../screens/netspecter_screen.dart';

class NetSpecterOverlay extends StatefulWidget {
  NetSpecterOverlay({
    super.key,
    InspectorSession? session,
    NetSpecterConfig? config,
    this.navigatorKey,
    this.customTrigger,
    required this.child,
  })  : session = session ?? InspectorSession.instance,
        config = config ?? const NetSpecterConfig();

  final InspectorSession session;
  final NetSpecterConfig config;

  /// The app's existing [GlobalKey<NavigatorState>].
  ///
  /// Pass the **same key** you registered on `MaterialApp` or `GoRouter`.
  /// The overlay stores it internally so that [NetSpecter.showInspector()]
  /// can push the inspector screen without a [BuildContext].
  ///
  /// ```dart
  /// // Your app already owns this key:
  /// final navigatorKey = GlobalKey<NavigatorState>();
  ///
  /// GoRouter(navigatorKey: navigatorKey, ...)
  ///
  /// NetSpecterOverlay(
  ///   navigatorKey: navigatorKey, // ← pass it here
  ///   child: ...,
  /// )
  /// ```
  ///
  /// If omitted, every navigation falls back to
  /// `Navigator.of(context, rootNavigator: true)` — which works fine for
  /// plain `MaterialApp` setups without a custom router.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// An arbitrary stream whose events open the inspector.
  ///
  /// Use this to wire any external trigger — local notification taps,
  /// remote config flags, custom gestures — without modifying the overlay.
  final Stream<void>? customTrigger;

  final Widget child;

  @override
  State<NetSpecterOverlay> createState() => _NetSpecterOverlayState();
}

class _NetSpecterOverlayState extends State<NetSpecterOverlay> {
  StreamSubscription<void>? _customTriggerSub;

  @override
  void initState() {
    super.initState();
    widget.session.initialize();
    // Store the developer's key so showInspector() can use it without context.
    if (widget.navigatorKey != null) {
      _registeredNavigatorKey = widget.navigatorKey;
    }
    _subscribeCustomTrigger();
  }

  @override
  void didUpdateWidget(NetSpecterOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigatorKey != widget.navigatorKey &&
        widget.navigatorKey != null) {
      _registeredNavigatorKey = widget.navigatorKey;
    }
    if (oldWidget.customTrigger != widget.customTrigger) {
      _customTriggerSub?.cancel();
      _subscribeCustomTrigger();
    }
  }

  void _subscribeCustomTrigger() {
    _customTriggerSub = widget.customTrigger?.listen((_) {
      if (mounted) _openInspector(context);
    });
  }

  @override
  void dispose() {
    _customTriggerSub?.cancel();
    super.dispose();
  }

  void _openInspector(BuildContext context) {
    openInspectorIfNotOpen(
      session: widget.session,
      nav: _registeredNavigatorKey?.currentState,
      context: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    final triggers = widget.config.triggers;
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final padding = mediaQuery.padding;

    Widget content = widget.child;

    if (triggers.contains(InspectorTrigger.longPress)) {
      content = RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(
              duration: widget.config.longPressDuration,
              debugOwner: this,
            ),
            (instance) {
              instance.onLongPress = () => _openInspector(context);
            },
          ),
        },
        child: content,
      );
    }

    if (triggers.contains(InspectorTrigger.shake)) {
      content = ShakeDetector(
        threshold: widget.config.shakeThreshold,
        minInterval: widget.config.shakeMinInterval,
        onShake: () => _openInspector(context),
        child: content,
      );
    }

    if (triggers.contains(InspectorTrigger.floatingButton)) {
      final fabChild = widget.config.fabChild ??
          const Icon(Icons.bug_report, size: 20, color: Colors.white);

      content = Stack(
        children: <Widget>[
          content,
          Positioned.fill(
            child: IgnorePointer(
              ignoring: false,
              child: DraggableFab(
                initPosition: Offset(screenSize.width, screenSize.height / 2),
                securityBottom: padding.bottom,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Material(
                    color: Colors.red,
                    elevation: 2,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _openInspector(context),
                      customBorder: const CircleBorder(),
                      child: Center(child: fabChild),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return content;
  }
}

/// The developer's navigator key, stored when [NetSpecterOverlay] is built.
///
/// Used by [NetSpecter.showInspector()] to navigate without a [BuildContext].
/// Null until the developer passes a key via [NetSpecterOverlay.navigatorKey].
GlobalKey<NavigatorState>? _registeredNavigatorKey;

/// Read-only access for [NetSpecter.showInspector].
GlobalKey<NavigatorState>? get registeredNavigatorKey => _registeredNavigatorKey;

/// True while the inspector screen is on the navigation stack.
///
/// Shared across all entry points (overlay triggers, [NetSpecter.showInspector])
/// so that no matter which trigger fires, only one inspector is ever pushed.
bool _inspectorIsOpen = false;

/// Pushes the inspector screen onto the navigator, unless it is already open.
///
/// All entry points ([_NetSpecterOverlayState], [NetSpecter.showInspector])
/// must route through this function so the guard is always enforced.
void openInspectorIfNotOpen({
  required InspectorSession session,
  NavigatorState? nav,
  BuildContext? context,
}) {
  if (_inspectorIsOpen) return;

  final navigator = nav ??
      _registeredNavigatorKey?.currentState ??
      (context != null
          ? Navigator.maybeOf(context, rootNavigator: true)
          : null);
  if (navigator == null) return;

  _inspectorIsOpen = true;
  navigator
      .push<void>(
        MaterialPageRoute<void>(
          builder: (_) => NetSpecterScreen(session: session),
        ),
      )
      .whenComplete(() => _inspectorIsOpen = false);
}
