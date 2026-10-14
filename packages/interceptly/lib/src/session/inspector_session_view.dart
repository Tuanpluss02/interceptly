import 'package:flutter/foundation.dart';

import '../model/domain_group.dart';
import '../model/interceptly_settings.dart';
import '../model/network_simulation.dart';
import '../model/realtime_frame.dart';
import '../model/request_filter.dart';
import '../model/request_record.dart';
import '../model/request_summary.dart';
import '../model/search_match_scope.dart';
import 'inspector_preferences.dart';

/// Public interface for reading and controlling the inspector session.
///
/// App developers depend on this type — not the concrete [InspectorSession].
/// Interceptors receive the concrete type internally.
abstract class InspectorSessionView extends ChangeNotifier {
  InterceptlySettings get settings;
  InspectorPreferences get preferences;

  List<RequestSummary> get entries;

  /// Monotonically increasing counter incremented on every entry addition, update, or clear.
  int get entriesVersion => 0;

  RequestFilter get filter;
  bool get isEnabled;
  int get droppedCount;
  NetworkSimulationProfile get networkSimulation;

  String? get masterQuery;
  bool get isMasterSearchActive;
  bool get isScanningBodies;
  bool get isScanningFiles;
  bool get groupingEnabled;

  /// Returns the scopes that matched the active master search query for the given record ID.
  Set<SearchMatchScope> getSearchScopes(String id) =>
      const <SearchMatchScope>{};

  /// Looks up an entry by its unique [id] in O(1) time on concrete sessions,
  /// with an O(N) fallback over [entries] on the base view interface.
  RequestSummary? byId(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Loads full details for the request record with [id].
  Future<RequestRecord> loadDetailById(String id) async {
    final summary = byId(id);
    if (summary != null) {
      return loadDetail(summary);
    }
    throw StateError('Record not found for id: $id');
  }

  Future<RequestRecord> loadDetail(RequestSummary summary);

  void enable();
  void disable();
  Future<void> clear();
  void applyFilter(RequestFilter filter);
  void clearFilter();
  void setNetworkSimulation(NetworkSimulationProfile profile);
  void clearNetworkSimulation();
  List<DomainGroup> getGroupedRecords();
  void toggleGrouping(bool enabled);
  void toggleDomainExpanded(String domain);
  void cancelMasterSearch();
  Future<void> startMasterSearch(String query);
  Set<String> get availableDomains;

  /// Returns captured realtime frames for the given [sessionId] in FIFO order.
  List<RealtimeFrame> getRealtimeFrames(String sessionId) =>
      const <RealtimeFrame>[];
}
