import 'dart:async';

import 'package:flutter/material.dart';
import '../model/interceptly_settings.dart';
import '../model/network_simulation.dart';
import '../model/raw_capture.dart';
import '../model/request_filter.dart';
import '../model/request_record.dart';
import '../model/request_summary.dart';
import '../session/inspector_session.dart';
import '../session/inspector_session_view.dart';
import '../ui/interceptly_theme.dart';
import '../ui/overlay/draggable_fab.dart';
import '../ui/screens/interceptly_screen.dart';
import '../ui/widgets/toast_notification.dart';

/// Thin public facade over [InspectorSession].
class Interceptly extends ChangeNotifier {
  Interceptly({InterceptlySettings? settings, InspectorSession? session})
      : _session = session ?? InspectorSession(settings: settings) {
    _session.addListener(notifyListeners);
  }

  static Interceptly? _sharedInstance;

  static Interceptly get instance {
    return _sharedInstance ??= Interceptly(session: InspectorSession.instance);
  }

  final InspectorSession _session;

  // ---------------------------------------------------------------------------
  // init / detach
  // ---------------------------------------------------------------------------

  /// Single entrypoint to initialize Interceptly: attaches the UI to [navigatorKey]
  /// and applies all desired configuration options in one clean call.
  ///
  /// ```dart
  /// Interceptly.init(
  ///   navigatorKey: _navKey,
  ///   settings: const InterceptlySettings(
  ///     maxBodyBytes: 1024 * 1024,
  ///     redactedHeaders: {'authorization', 'x-api-key'},
  ///   ),
  ///   showFloatingButton: true,
  /// );
  /// ```
  static Future<void> init({
    required GlobalKey<NavigatorState> navigatorKey,
    bool showFloatingButton = true,
    Widget? fabChild,
    Stream<void>? customTrigger,
    InterceptlySettings settings = const InterceptlySettings(),
    InspectorSession? session,
  }) {
    final targetSession = session ?? InspectorSession.instance;
    targetSession.configureSession(settings);

    return _init(
      navigatorKey: navigatorKey,
      session: targetSession,
      showFloatingButton: showFloatingButton,
      fabChild: fabChild,
      customTrigger: customTrigger,
    );
  }

  /// Optional [NavigatorObserver] to ensure the floating button stays on top
  /// across route transitions.
  static final NavigatorObserver navigatorObserver =
      _InterceptlyNavigatorObserver();

  /// Removes all overlay entries and cancels all trigger subscriptions.
  static void detach() => _detach();

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  /// Opens the inspector screen.
  ///
  /// Pass a [context] only if [init] has not been called yet.
  static void showInspector([BuildContext? context]) {
    assert(
      _state.navigatorKey != null || context != null,
      'Interceptly.showInspector() requires either a BuildContext or a prior '
      'call to Interceptly.init().',
    );
    _pushInspector(
      session: InspectorSession.instance,
      nav: _state.navigatorKey?.currentState,
      context: context,
    );
  }

  // ---------------------------------------------------------------------------
  // Passthrough getters
  // ---------------------------------------------------------------------------

  InspectorSessionView get session => _session;
  InterceptlySettings get settings => _session.settings;
  List<RequestSummary> get calls => _session.entries;
  RequestFilter get filter => _session.filter;
  int get droppedEvents => _session.droppedCount;
  bool get isEnabled => _session.isEnabled;
  NetworkSimulationProfile get networkSimulation => _session.networkSimulation;

  // ---------------------------------------------------------------------------
  // Capture control
  // ---------------------------------------------------------------------------

  void enable() => _session.enable();
  void disable() => _session.disable();
  Future<void> initialize() => _session.initialize();
  void recordCapture(RawCapture capture) => _session.record(capture);
  Future<RequestRecord> loadDetail(RequestSummary summary) =>
      _session.loadDetail(summary);
  void applyFilter(RequestFilter filter) => _session.applyFilter(filter);
  void setNetworkSimulation(NetworkSimulationProfile profile) =>
      _session.setNetworkSimulation(profile);
  void clearNetworkSimulation() => _session.clearNetworkSimulation();
  Future<void> clear() => _session.clear();

  @override
  void dispose() {
    _session.removeListener(notifyListeners);
    if (identical(_sharedInstance, this)) {
      _sharedInstance = null;
    }
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// UI State & Overlay Wiring
// ---------------------------------------------------------------------------

final _state = _AttachState();

class _InterceptlyLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeMetrics() {
    _tryInsertOverlays();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tryInsertOverlays();
    }
  }
}

class _InterceptlyNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _scheduleCheck();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _scheduleCheck();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _scheduleCheck();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _scheduleCheck();
  }

  void _scheduleCheck() {
    if (_state.showFloatingButton && !_state.inspectorIsOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryInsertOverlays();
      });
    }
  }
}

final _lifecycleObserver = _InterceptlyLifecycleObserver();

class _AttachState {
  GlobalKey<NavigatorState>? navigatorKey;
  InspectorSession? session;
  bool showFloatingButton = true;
  Widget? fabChild;
  OverlayEntry? fabEntry;
  StreamSubscription<void>? customTriggerSub;
  bool inspectorIsOpen = false;
  bool observerAttached = false;
  bool initialRouteBroughtToTop = false;

  void reset() {
    if (observerAttached) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver);
      observerAttached = false;
    }
    fabEntry?.remove();
    fabEntry = null;
    customTriggerSub?.cancel();
    customTriggerSub = null;
    navigatorKey = null;
    session = null;
    showFloatingButton = true;
    fabChild = null;
    inspectorIsOpen = false;
    initialRouteBroughtToTop = false;
  }
}

Future<void> _init({
  required GlobalKey<NavigatorState> navigatorKey,
  InspectorSession? session,
  bool showFloatingButton = true,
  Widget? fabChild,
  Stream<void>? customTrigger,
}) async {
  _state.reset();

  _state.navigatorKey = navigatorKey;
  _state.session = session ?? InspectorSession.instance;
  _state.showFloatingButton = showFloatingButton;
  _state.fabChild = fabChild;

  if (!_state.observerAttached) {
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _state.observerAttached = true;
  }

  ToastNotification.setNavigatorKey(navigatorKey);
  await _state.session!.initialize();

  if (customTrigger != null) {
    _state.customTriggerSub = customTrigger.listen((_) => _openInspector());
  }

  WidgetsBinding.instance.addPostFrameCallback((_) => _tryInsertOverlays());
}

void _detach() => _state.reset();

void _openInspector() {
  _pushInspector(
    session: _state.session ?? InspectorSession.instance,
    nav: _state.navigatorKey?.currentState,
  );
}

void _pushInspector({
  required InspectorSessionView session,
  NavigatorState? nav,
  BuildContext? context,
}) {
  if (_state.inspectorIsOpen) return;

  final navigator = nav ??
      (context != null
          ? Navigator.maybeOf(context, rootNavigator: true)
          : null);
  if (navigator == null) return;

  _state.inspectorIsOpen = true;
  navigator
      .push<void>(
        MaterialPageRoute<void>(
          builder: (_) => InterceptlyScreen(session: session),
        ),
      )
      .whenComplete(() {
        _state.inspectorIsOpen = false;
        _tryInsertOverlays();
      });
}

void _tryInsertOverlays([int attempt = 0]) {
  if (!_state.showFloatingButton) return;

  final overlay = _state.navigatorKey?.currentState?.overlay;
  if (overlay == null || !overlay.mounted) {
    if (attempt < 120) {
      final delayMs = attempt < 20 ? 100 : 500;
      Future.delayed(
        Duration(milliseconds: delayMs),
        () => _tryInsertOverlays(attempt + 1),
      );
    }
    return;
  }

  if (_state.fabEntry != null && !_state.fabEntry!.mounted) {
    _state.fabEntry = null;
    _state.initialRouteBroughtToTop = false;
  }

  if (_state.fabEntry == null) {
    _insertFab(overlay);
    if (!_state.initialRouteBroughtToTop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_state.initialRouteBroughtToTop) {
          _state.initialRouteBroughtToTop = true;
          _bringFabToTop();
        }
      });
    }
  }
}

void _bringFabToTop() {
  if (_state.inspectorIsOpen || !_state.showFloatingButton) return;
  final entry = _state.fabEntry;
  final overlay = _state.navigatorKey?.currentState?.overlay;
  if (entry == null || !entry.mounted || overlay == null || !overlay.mounted) {
    return;
  }

  entry.remove();
  overlay.insert(entry);
}

void _insertFab(OverlayState overlay) {
  if (!overlay.mounted) return;
  _state.fabEntry = OverlayEntry(
    builder: (context) {
      final fabChild = _state.fabChild ??
          const Icon(
            Icons.bug_report,
            size: 20,
            color: InterceptlyGlobalColor.white,
          );
      final mq = MediaQuery.of(context);
      return Positioned.fill(
        child: IgnorePointer(
          ignoring: false,
          child: DraggableFab(
            initPosition: Offset(mq.size.width, mq.size.height / 2),
            securityBottom: mq.padding.bottom,
            securityTop: mq.padding.top,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Material(
                color: InterceptlyGlobalColor.red500,
                elevation: 2,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _openInspector,
                  customBorder: const CircleBorder(),
                  child: Center(child: fabChild),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  overlay.insert(_state.fabEntry!);
}
