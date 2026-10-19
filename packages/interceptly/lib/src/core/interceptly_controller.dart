import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/interceptly_engine.dart';
import '../model/interceptly_settings.dart';
import '../model/network_simulation.dart';
import '../model/request_record.dart';
import '../model/request_summary.dart';
import '../ui/overlay/floating_overlay_manager.dart';
import '../ui/screens/interceptly_screen.dart';
import '../ui/widgets/toast_notification.dart';

/// Central public facade for Interceptly.
///
/// Provides initialization, overlay control, and high-level session management.
class Interceptly {
  Interceptly._();

  /// The underlying headless data engine singleton.
  static InterceptlyEngine get engine => InterceptlyEngine.instance;

  /// Returns the shared Interceptly controller instance.
  static Interceptly get instance => _sharedInstance;
  static final Interceptly _sharedInstance = Interceptly._();

  /// Resets the underlying engine and overlays for isolated unit/widget tests.
  static Future<void> resetForTesting() async {
    _detach();
    await InterceptlyEngine.resetForTesting();
  }

  /// Single entrypoint to initialize Interceptly: attaches the UI to [navigatorKey]
  /// and applies all desired configuration options in one clean call.
  static Future<void> init({
    required GlobalKey<NavigatorState> navigatorKey,
    bool showFloatingButton = true,
    Widget? fabChild,
    Stream<void>? customTrigger,
    InterceptlySettings? settings,
  }) {
    if (settings != null) engine.configure(settings);

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
  InterceptlySettings get settings => engine.settings;

  /// Applies [settings] to the underlying engine.
  void configure(InterceptlySettings settings) => engine.configure(settings);

  /// List of captured entries in newest-first order.
  List<RequestSummary> get entries => engine.entries;

  /// List of captured calls (alias for [entries]).
  List<RequestSummary> get calls => engine.entries;

  /// Count of dropped events due to buffer overflows.
  int get droppedEvents => engine.droppedCount;

  /// Whether traffic capture is currently enabled.
  bool get isEnabled => engine.isEnabled;

  /// Current network simulation profile.
  NetworkSimulationProfile get networkSimulation => engine.networkSimulation;

  /// Enables traffic capture.
  void enable() => engine.enable();

  /// Disables traffic capture.
  void disable() => engine.disable();

  /// Initializes background workers and disk storage.
  Future<void> initialize() => engine.initialize();

  /// Loads full details for [summary].
  Future<RequestRecord> loadDetail(RequestSummary summary) =>
      engine.loadDetail(summary);

  /// Sets an active network simulation profile.
  void setNetworkSimulation(NetworkSimulationProfile profile) =>
      engine.setNetworkSimulation(profile);

  /// Clears active network simulation profile.
  void clearNetworkSimulation() => engine.clearNetworkSimulation();

  /// Clears all captured REST and realtime calls.
  Future<void> clear() => engine.clear();

  /// Clears only REST traffic.
  Future<void> clearRest() => engine.clearRest();

  /// Clears only realtime traffic.
  Future<void> clearRealtime() => engine.clearRealtime();
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
