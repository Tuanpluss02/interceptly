import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../capture/dio/interceptly_dio_interceptor.dart';
import '../capture/http/interceptly_http_client.dart';
import '../model/http_call_filter.dart';
import '../model/index_entry.dart';
import '../model/interceptly_settings.dart';
import '../model/network_simulation.dart';
import '../model/raw_capture.dart';
import '../model/request_record.dart';
import '../storage/inspector_session.dart';
import '../ui/overlay/interceptly_overlay.dart'
    show openInspectorIfNotOpen, registeredNavigatorKey;

export '../storage/inspector_session.dart' show InspectorSession;

/// Thin public facade over [InspectorSession].
///
/// Exposes a stable API surface for users who prefer `Interceptly.xxx` style
/// calls. All state lives in [InspectorSession]; this class has no extra state.
class Interceptly extends ChangeNotifier {
  Interceptly({
    InterceptlySettings? settings,
    InspectorSession? session,
  }) : _session = session ?? InspectorSession(settings: settings) {
    _session.addListener(notifyListeners);
  }

  static Interceptly? _sharedInstance;

  /// The shared singleton instance backed by [InspectorSession.instance].
  static Interceptly get instance {
    return _sharedInstance ??= Interceptly(
      session: InspectorSession.instance,
    );
  }

  final InspectorSession _session;

  // ---------------------------------------------------------------------------
  // Passthrough getters
  // ---------------------------------------------------------------------------

  /// Underlying session that owns captured data and settings.
  InspectorSession get session => _session;

  /// Effective capture and storage settings.
  InterceptlySettings get settings => _session.settings;

  /// Current list of indexed network calls.
  List<IndexEntry> get calls => _session.entries;

  /// Active filter used by the inspector list.
  HttpCallFilter get filter => _session.filter;

  /// Number of events dropped due to bounded queue pressure.
  int get droppedEvents => _session.droppedCount;

  /// Whether capture is currently enabled.
  bool get isEnabled => _session.isEnabled;

  /// Active network simulation profile.
  NetworkSimulationProfile get networkSimulation => _session.networkSimulation;

  // ---------------------------------------------------------------------------
  // Capture control
  // ---------------------------------------------------------------------------

  /// Enables request capture. Capture is enabled by default.
  void enable() => _session.enable();

  /// Disables request capture without removing the interceptor.
  ///
  /// The interceptor keeps running but all [recordCapture] calls are silently
  /// dropped. Useful for sensitive screens (e.g. payment flows).
  void disable() => _session.disable();

  /// Initializes background resources used by the session.
  Future<void> initialize() => _session.initialize();

  /// Records a completed capture payload.
  void recordCapture(RawCapture capture) => _session.record(capture);

  /// Loads full request/response detail for an indexed entry.
  Future<RequestRecord> loadDetail(IndexEntry entry) =>
      _session.loadDetail(entry);

  /// Applies list filtering in the inspector UI.
  void applyFilter(HttpCallFilter filter) => _session.applyFilter(filter);

  /// Sets runtime network simulation to [profile].
  void setNetworkSimulation(NetworkSimulationProfile profile) =>
      _session.setNetworkSimulation(profile);

  /// Clears simulation and returns to no-throttling behavior.
  void clearNetworkSimulation() => _session.clearNetworkSimulation();

  /// Clears captured entries and body storage for the current session.
  Future<void> clear() => _session.clear();

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  /// Opens the inspector screen.
  ///
  /// Uses the navigator key registered via [InterceptlyOverlay.navigatorKey]
  /// if available, otherwise falls back to [context].
  ///
  /// ```dart
  /// // From a button (context always available):
  /// Interceptly.showInspector(context);
  ///
  /// // From a notification handler (navigatorKey must have been passed to
  /// // InterceptlyOverlay first):
  /// Interceptly.showInspector();
  /// ```
  static void showInspector([BuildContext? context]) {
    assert(
      registeredNavigatorKey != null || context != null,
      'Interceptly.showInspector() requires either a BuildContext or a '
      'navigatorKey passed to InterceptlyOverlay.',
    );
    openInspectorIfNotOpen(
      session: InspectorSession.instance,
      nav: registeredNavigatorKey?.currentState,
      context: context,
    );
  }

  // ---------------------------------------------------------------------------
  // Interceptor / client factories
  // ---------------------------------------------------------------------------

  /// A ready-to-use Dio interceptor backed by [InspectorSession.instance].
  ///
  /// ```dart
  /// dio.interceptors.add(Interceptly.dioInterceptor);
  /// ```
  static InterceptlyDioInterceptor get dioInterceptor =>
      InterceptlyDioInterceptor(InspectorSession.instance);

  /// Wraps an [http.Client] so all its requests are captured.
  ///
  /// ```dart
  /// final client = Interceptly.wrapHttpClient(http.Client());
  /// ```
  static InterceptlyHttpClient wrapHttpClient(http.Client inner) =>
      InterceptlyHttpClient.wrap(inner, InspectorSession.instance);

  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _session.removeListener(notifyListeners);
    super.dispose();
  }
}
