import 'dart:async';

import 'package:flutter/material.dart';
import '../model/interceptly_settings.dart';
import '../model/network_simulation.dart';
import '../model/raw_capture.dart';
import '../model/request_filter.dart';
import '../model/request_record.dart';
import '../model/request_summary.dart';
import '../session/inspector_preferences.dart';
import '../session/inspector_session.dart';
import '../session/inspector_session_view.dart';
import '../ui/interceptly_theme.dart';
import '../ui/overlay/draggable_fab.dart';
import '../ui/screens/interceptly_screen.dart';
import '../ui/trigger/interceptly_config.dart';
import '../ui/widgets/toast_notification.dart';

part 'interceptly_attach.dart';

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
  // attach / detach
  // ---------------------------------------------------------------------------

  /// Configures global settings for Interceptly.
  static void configure(InterceptlySettings settings) {
    InspectorSession.configure(settings);
  }

  /// Attaches Interceptly to the running app without wrapping the widget tree.
  ///
  /// Call once after the navigator is ready — e.g. in a `addPostFrameCallback`
  /// right after `runApp`:
  ///
  /// ```dart
  /// runApp(MyApp(navigatorKey: _navKey));
  /// WidgetsBinding.instance.addPostFrameCallback((_) {
  ///   Interceptly.attach(navigatorKey: _navKey);
  /// });
  /// ```
  static Future<void> attach({
    required GlobalKey<NavigatorState> navigatorKey,
    InspectorSession? session,
    InterceptlySettings? settings,
    InterceptlyConfig? config,
    bool? showFloatingButton,
    Widget? fabChild,
    Stream<void>? customTrigger,
  }) {
    if (settings != null) {
      InspectorSession.configure(settings);
    }
    final effectiveConfig = (showFloatingButton != null || fabChild != null)
        ? InterceptlyConfig(
            showFloatingButton:
                showFloatingButton ?? config?.showFloatingButton ?? true,
            fabChild: fabChild ?? config?.fabChild,
          )
        : config;
    return _attach(
      navigatorKey: navigatorKey,
      session: session,
      config: effectiveConfig,
      customTrigger: customTrigger,
    );
  }

  /// Removes all overlay entries and cancels all trigger subscriptions.
  static void detach() => _detach();

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  /// Opens the inspector screen.
  ///
  /// Pass a [context] only if [attach] has not been called yet.
  static void showInspector([BuildContext? context]) {
    assert(
      _state.navigatorKey != null || context != null,
      'Interceptly.showInspector() requires either a BuildContext or a prior '
      'call to Interceptly.attach().',
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
  InspectorPreferences get preferences => _session.preferences;
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
