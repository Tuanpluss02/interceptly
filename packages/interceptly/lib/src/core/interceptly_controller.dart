import 'dart:async';

import 'package:flutter/material.dart';
import '../model/interceptly_settings.dart';
import '../model/network_simulation.dart';
import '../model/raw_capture.dart';
import '../model/realtime_frame.dart';
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

  /// Single entrypoint to initialize Interceptly: attaches the UI to [navigatorKey]
  /// and applies all desired configuration options in one clean call.
  ///
  /// Release build checklist:
  /// - Configure payload size caps via [InterceptlySettings.maxBodyBytes] and
  ///   [InterceptlySettings.maxEntries] to avoid memory overhead.
  /// - Keep the floating overlay hidden or restricted to internal users when shipping.
  ///
  /// Pass [settings] only to (re)configure capture behavior; when omitted the
  /// session keeps whatever configuration it already has.
  ///
  /// ```dart
  /// Interceptly.init(
  ///   navigatorKey: _navKey,
  ///   settings: const InterceptlySettings(
  ///     maxBodyBytes: 1024 * 1024,
  ///   ),
  ///   showFloatingButton: true,
  /// );
  /// ```
  static Future<void> init({
    required GlobalKey<NavigatorState> navigatorKey,
    bool showFloatingButton = true,
    Widget? fabChild,
    Stream<void>? customTrigger,
    InterceptlySettings? settings,
    InspectorSession? session,
  }) {
    final targetSession = session ?? InspectorSession.instance;
    if (settings != null) targetSession.configureSession(settings);

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

  /// Hides the floating button for the remainder of this session.
  /// It will reappear when the app restarts.
  static void hideFloatingButtonForSession() =>
      FloatingOverlayManager.instance.setHiddenForSession(true);

  /// Restores the floating button if it was hidden for this session.
  static void showFloatingButtonForSession() =>
      FloatingOverlayManager.instance.setHiddenForSession(false);

  /// Whether the floating button is currently hidden for this session.
  static bool get isFloatingButtonHiddenForSession =>
      FloatingOverlayManager.instance.isHiddenForSession;

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

  InspectorSessionView get session => _session;
  InterceptlySettings get settings => _session.settings;
  List<RequestSummary> get calls => _session.entries;
  RequestFilter get filter => _session.filter;
  int get droppedEvents => _session.droppedCount;
  bool get isEnabled => _session.isEnabled;
  NetworkSimulationProfile get networkSimulation => _session.networkSimulation;

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

  /// Enqueues a captured [RealtimeFrame] into the session buffer.
  void recordRealtimeFrame(RealtimeFrame frame) =>
      _session.recordRealtimeFrame(frame);

  /// Returns captured realtime frames for the given [sessionId] in FIFO order.
  List<RealtimeFrame> getRealtimeFrames(String sessionId) =>
      _session.getRealtimeFrames(sessionId);

  /// Alias for [getRealtimeFrames].
  List<RealtimeFrame> getFrames(String sessionId) =>
      _session.getFrames(sessionId);

  /// Records opening of a realtime connection (e.g. WebSocket handshake).
  void recordRealtimeConnection({
    required String id,
    required String url,
    Map<String, String> headers = const {},
    DateTime? timestamp,
  }) =>
      _session.recordRealtimeConnection(
        id: id,
        url: url,
        headers: headers,
        timestamp: timestamp,
      );

  /// Records closing of an active realtime connection with close code and reason.
  void closeRealtimeConnection(
    String id, {
    int closeCode = 1000,
    String? closeReason,
  }) =>
      _session.closeRealtimeConnection(
        id,
        closeCode: closeCode,
        closeReason: closeReason,
      );

  @override
  void dispose() {
    _session.removeListener(notifyListeners);
    if (identical(_sharedInstance, this)) {
      _sharedInstance = null;
    }
    super.dispose();
  }
}

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
