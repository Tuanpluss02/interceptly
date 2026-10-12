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
import '../ui/overlay/floating_overlay_manager.dart';
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
  static NavigatorObserver get navigatorObserver =>
      FloatingOverlayManager.instance.navigatorObserver;

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
      _activeNavigatorKey != null || context != null,
      'Interceptly.showInspector() requires either a BuildContext or a prior '
      'call to Interceptly.init().',
    );
    _pushInspector(
      session: InspectorSession.instance,
      nav: _activeNavigatorKey?.currentState,
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
// UI State & Overlay Wiring (Delegated to FloatingOverlayManager)
// ---------------------------------------------------------------------------

GlobalKey<NavigatorState>? _activeNavigatorKey;
InspectorSession? _activeSession;
StreamSubscription<void>? _customTriggerSub;
bool _inspectorIsOpen = false;

Future<void> _init({
  required GlobalKey<NavigatorState> navigatorKey,
  InspectorSession? session,
  bool showFloatingButton = true,
  Widget? fabChild,
  Stream<void>? customTrigger,
}) async {
  _detach();

  _activeNavigatorKey = navigatorKey;
  _activeSession = session ?? InspectorSession.instance;

  ToastNotification.setNavigatorKey(navigatorKey);

  if (customTrigger != null) {
    _customTriggerSub = customTrigger.listen((_) => _openInspector());
  }

  FloatingOverlayManager.instance.attach(
    navigatorKey: navigatorKey,
    showFloatingButton: showFloatingButton,
    fabChild: fabChild,
    onFabTap: _openInspector,
  );

  unawaited(_activeSession!.initialize().catchError((Object error) {
    debugPrint('[Interceptly] background init failed: $error');
  }));
}

void _detach() {
  FloatingOverlayManager.instance.detach();
  _customTriggerSub?.cancel();
  _customTriggerSub = null;
  _activeNavigatorKey = null;
  _activeSession = null;
  _inspectorIsOpen = false;
}

void _openInspector() {
  _pushInspector(
    session: _activeSession ?? InspectorSession.instance,
    nav: _activeNavigatorKey?.currentState,
  );
}

void _pushInspector({
  required InspectorSessionView session,
  NavigatorState? nav,
  BuildContext? context,
}) {
  if (_inspectorIsOpen) return;

  final navigator = nav ??
      (context != null
          ? Navigator.maybeOf(context, rootNavigator: true)
          : null);
  if (navigator == null) return;

  _inspectorIsOpen = true;
  FloatingOverlayManager.instance.onInspectorOpened();
  navigator
      .push<void>(
    MaterialPageRoute<void>(
      builder: (_) => InterceptlyScreen(session: session),
    ),
  )
      .whenComplete(() {
    _inspectorIsOpen = false;
    FloatingOverlayManager.instance.onInspectorClosed();
  });
}
