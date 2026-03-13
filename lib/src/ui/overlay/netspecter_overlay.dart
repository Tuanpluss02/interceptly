import 'dart:async';

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
    this.customTrigger,
    required this.child,
  })  : session = session ?? InspectorSession.instance,
        config = config ?? const NetSpecterConfig();

  final InspectorSession session;
  final NetSpecterConfig config;

  /// An arbitrary stream whose events open the inspector.
  ///
  /// Use this to wire any external trigger — local notifications, remote
  /// config flags, custom gestures — without modifying the overlay widget.
  ///
  /// ```dart
  /// final _triggerController = StreamController<void>.broadcast();
  ///
  /// // Wire to a local notification tap:
  /// onNotificationTap: (_) => _triggerController.add(null),
  ///
  /// NetSpecterOverlay(
  ///   customTrigger: _triggerController.stream,
  ///   child: ...,
  /// )
  /// ```
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
    _subscribeCustomTrigger();
  }

  @override
  void didUpdateWidget(NetSpecterOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    final route = MaterialPageRoute<void>(
      builder: (_) => NetSpecterScreen(session: widget.session),
    );
    final nav = netSpecterNavigatorKey.currentState;
    if (nav != null) {
      nav.push(route);
    } else {
      Navigator.of(context, rootNavigator: true).push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final triggers = widget.config.triggers;
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final padding = mediaQuery.padding;

    Widget content = widget.child;

    // Long-press trigger: wraps child in a transparent GestureDetector.
    if (triggers.contains(InspectorTrigger.longPress)) {
      content = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () => _openInspector(context),
        child: content,
      );
    }

    // Shake trigger: wraps in the accelerometer listener widget.
    if (triggers.contains(InspectorTrigger.shake)) {
      content = ShakeDetector(
        threshold: widget.config.shakeThreshold,
        minInterval: widget.config.shakeMinInterval,
        onShake: () => _openInspector(context),
        child: content,
      );
    }

    // Floating button trigger: overlay the DraggableFab on top.
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

/// A [GlobalKey] that can be registered as `MaterialApp.navigatorKey`.
///
/// When registered, [NetSpecterOverlay] uses this key to push inspector
/// screens, enabling correct navigation with GoRouter.
final GlobalKey<NavigatorState> _kNavigatorKey = GlobalKey<NavigatorState>();

GlobalKey<NavigatorState> get netSpecterNavigatorKey => _kNavigatorKey;
