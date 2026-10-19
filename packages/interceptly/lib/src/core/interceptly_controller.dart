import 'dart:async';

import 'package:flutter/material.dart';
import '../model/interceptly_settings.dart';
import '../model/network_simulation.dart';
import '../model/raw_capture.dart';
import '../model/realtime_frame.dart';
import '../model/request_record.dart';
import '../model/request_summary.dart';
import '../ui/overlay/floating_overlay_manager.dart';
import '../ui/screens/interceptly_screen.dart';
import '../ui/widgets/toast_notification.dart';
import 'interceptly_engine.dart';

/// Central public facade for Interceptly.
///
/// Provides initialization, overlay control, and testing hooks for application code.
class Interceptly extends ChangeNotifier {
  /// Creates an [Interceptly] controller backed by [InterceptlyEngine.instance].
  Interceptly({InterceptlySettings? settings})
      : _engine = InterceptlyEngine.instance {
    if (settings != null) {
      _engine.configure(settings);
    }
    _engine.addListener(notifyListeners);
  }

  static Interceptly? _sharedInstance;

  /// Returns the shared Interceptly singleton instance.
  static Interceptly get instance {
    return _sharedInstance ??= Interceptly();
  }

  /// Resets the shared instance and underlying engine for isolated unit/widget tests.
  @visibleForTesting
  static Future<void> resetForTesting() async {
    _detach();
    _sharedInstance?.dispose();
    _sharedInstance = null;
    await InterceptlyEngine.resetForTesting();
  }

  final InterceptlyEngine _engine;

  /// Single entrypoint to initialize Interceptly: attaches the UI to [navigatorKey]
  /// and applies all desired configuration options in one clean call.
  static Future<void> init({
    required GlobalKey<NavigatorState> navigatorKey,
    bool showFloatingButton = true,
    Widget? fabChild,
    Stream<void>? customTrigger,
    InterceptlySettings? settings,
  }) {
    if (settings != null) InterceptlyEngine.instance.configure(settings);

    return _init(
      navigatorKey: navigatorKey,
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

  /// Hides the floating button for the remainder of this app session.
  /// It will reappear when the app restarts.
  static void hideFloatingButtonForSession() =>
      FloatingOverlayManager.instance.setHiddenForSession(true);

  /// Restores the floating button if it was hidden for this app session.
  static void showFloatingButtonForSession() =>
      FloatingOverlayManager.instance.setHiddenForSession(false);

  /// Whether the floating button is currently hidden for this app session.
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
      nav: _activeNavigatorKey?.currentState,
      context: context,
    );
  }

  /// Current settings active on the engine.
  InterceptlySettings get settings => _engine.settings;

  /// Applies [settings] to the underlying engine.
  void configure(InterceptlySettings settings) => _engine.configure(settings);

  /// List of captured calls.
  List<RequestSummary> get calls => _engine.entries;

  /// List of captured entries (alias for [calls]).
  List<RequestSummary> get entries => _engine.entries;

  /// Count of dropped events due to buffer overflows.
  int get droppedEvents => _engine.droppedCount;

  /// Whether traffic capture is currently enabled.
  bool get isEnabled => _engine.isEnabled;

  /// Current network simulation profile.
  NetworkSimulationProfile get networkSimulation => _engine.networkSimulation;

  /// Enables traffic capture.
  void enable() => _engine.enable();

  /// Disables traffic capture.
  void disable() => _engine.disable();

  /// Initializes background workers and disk storage.
  Future<void> initialize() => _engine.initialize();

  /// Enqueues [capture] for asynchronous background processing.
  void recordCapture(RawCapture capture) => _engine.record(capture);

  /// Loads full details for [summary].
  Future<RequestRecord> loadDetail(RequestSummary summary) =>
      _engine.loadDetail(summary);

  /// Loads full details for request with [id].
  Future<RequestRecord> loadDetailById(String id) =>
      _engine.loadDetailById(id);

  /// Sets an active network simulation profile.
  void setNetworkSimulation(NetworkSimulationProfile profile) =>
      _engine.setNetworkSimulation(profile);

  /// Clears active network simulation profile.
  void clearNetworkSimulation() => _engine.clearNetworkSimulation();

  /// Clears all captured REST and realtime calls.
  Future<void> clear() => _engine.clear();

  /// Clears only REST traffic.
  Future<void> clearRest() => _engine.clearRest();

  /// Clears only realtime traffic.
  Future<void> clearRealtime() => _engine.clearRealtime();

  /// Enqueues a captured [RealtimeFrame] into the engine buffer.
  Future<void> recordRealtimeFrame(RealtimeFrame frame) =>
      _engine.recordRealtimeFrame(frame);

  /// Returns captured realtime frames for the given connection [sessionId] in FIFO order.
  List<RealtimeFrame> getRealtimeFrames(String sessionId) =>
      _engine.getRealtimeFrames(sessionId);

  /// Records opening of a realtime connection (e.g. WebSocket handshake).
  void recordRealtimeConnection({
    required String id,
    required String url,
    Map<String, String> headers = const {},
    DateTime? timestamp,
  }) =>
      _engine.recordRealtimeConnection(
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
      _engine.closeRealtimeConnection(
        id,
        closeCode: closeCode,
        closeReason: closeReason,
      );

  @override
  void dispose() {
    _engine.removeListener(notifyListeners);
    if (identical(_sharedInstance, this)) {
      _sharedInstance = null;
    }
    super.dispose();
  }
}

GlobalKey<NavigatorState>? _activeNavigatorKey;
StreamSubscription<void>? _customTriggerSub;
bool _inspectorIsOpen = false;

Future<void> _init({
  required GlobalKey<NavigatorState> navigatorKey,
  bool showFloatingButton = true,
  Widget? fabChild,
  Stream<void>? customTrigger,
}) async {
  _detach();

  _activeNavigatorKey = navigatorKey;

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

  unawaited(InterceptlyEngine.instance.initialize().catchError((Object error) {
    debugPrint('[Interceptly] background init failed: $error');
  }));
}

void _detach() {
  FloatingOverlayManager.instance.detach();
  _customTriggerSub?.cancel();
  _customTriggerSub = null;
  _activeNavigatorKey = null;
  _inspectorIsOpen = false;
}

void _openInspector() {
  _pushInspector(
    nav: _activeNavigatorKey?.currentState,
  );
}

void _pushInspector({
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
      builder: (_) => const InterceptlyScreen(),
    ),
  )
      .whenComplete(() {
    _inspectorIsOpen = false;
    FloatingOverlayManager.instance.onInspectorClosed();
  });
}
