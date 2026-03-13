import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../capture/dio/netspecter_dio_interceptor.dart';
import '../capture/http/netspecter_http_client.dart';
import '../model/http_call_filter.dart';
import '../model/index_entry.dart';
import '../model/net_specter_settings.dart';
import '../model/raw_capture.dart';
import '../model/request_record.dart';
import '../storage/inspector_session.dart';
import '../ui/overlay/netspecter_overlay.dart'
    show openInspectorIfNotOpen, registeredNavigatorKey;

export '../storage/inspector_session.dart' show InspectorSession;

/// Thin public facade over [InspectorSession].
///
/// Exposes a stable API surface for users who prefer `NetSpecter.xxx` style
/// calls. All state lives in [InspectorSession]; this class has no extra state.
class NetSpecter extends ChangeNotifier {
  NetSpecter({
    NetSpecterSettings? settings,
    InspectorSession? session,
  }) : _session = session ?? InspectorSession(settings: settings) {
    _session.addListener(notifyListeners);
  }

  static NetSpecter? _sharedInstance;

  /// The shared singleton instance backed by [InspectorSession.instance].
  static NetSpecter get instance {
    return _sharedInstance ??= NetSpecter(
      session: InspectorSession.instance,
    );
  }


  final InspectorSession _session;

  // ---------------------------------------------------------------------------
  // Passthrough getters
  // ---------------------------------------------------------------------------

  InspectorSession get session => _session;
  NetSpecterSettings get settings => _session.settings;
  List<IndexEntry> get calls => _session.entries;
  HttpCallFilter get filter => _session.filter;
  int get droppedEvents => _session.droppedCount;
  bool get isEnabled => _session.isEnabled;

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

  Future<void> initialize() => _session.initialize();

  void recordCapture(RawCapture capture) => _session.record(capture);

  Future<RequestRecord> loadDetail(IndexEntry entry) =>
      _session.loadDetail(entry);

  void applyFilter(HttpCallFilter filter) => _session.applyFilter(filter);

  Future<void> clear() => _session.clear();

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  /// Opens the inspector screen.
  ///
  /// Prefers [navigatorKey] if registered; falls back to [context].
  ///
  /// ```dart
  /// // From a button:
  /// NetSpecter.showInspector(context);
  ///
  /// // From a notification handler (navigatorKey must be registered):
  /// NetSpecter.showInspector();
  /// ```
  /// Opens the inspector screen.
  ///
  /// Uses the navigator key registered via [NetSpecterOverlay.navigatorKey]
  /// if available, otherwise falls back to [context].
  ///
  /// ```dart
  /// // From a button (context always available):
  /// NetSpecter.showInspector(context);
  ///
  /// // From a notification handler (navigatorKey must have been passed to
  /// // NetSpecterOverlay first):
  /// NetSpecter.showInspector();
  /// ```
  static void showInspector([BuildContext? context]) {
    assert(
      registeredNavigatorKey != null || context != null,
      'NetSpecter.showInspector() requires either a BuildContext or a '
      'navigatorKey passed to NetSpecterOverlay.',
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
  /// dio.interceptors.add(NetSpecter.dioInterceptor);
  /// ```
  static NetSpecterDioInterceptor get dioInterceptor =>
      NetSpecterDioInterceptor(InspectorSession.instance);

  /// Wraps an [http.Client] so all its requests are captured.
  ///
  /// ```dart
  /// final client = NetSpecter.wrapHttpClient(http.Client());
  /// ```
  static NetSpecterHttpClient wrapHttpClient(http.Client inner) =>
      NetSpecterHttpClient.wrap(inner, InspectorSession.instance);

  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _session.removeListener(notifyListeners);
    super.dispose();
  }
}
