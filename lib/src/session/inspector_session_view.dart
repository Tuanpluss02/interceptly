import 'package:flutter/foundation.dart';

import '../model/domain_group.dart';
import '../model/interceptly_settings.dart';
import '../model/network_simulation.dart';
import '../model/request_filter.dart';
import '../model/request_record.dart';
import '../model/request_summary.dart';
import 'inspector_preferences.dart';

/// Public interface for reading and controlling the inspector session.
///
/// App developers depend on this type — not the concrete [InspectorSession].
/// Interceptors receive the concrete type internally.
abstract class InspectorSessionView extends ChangeNotifier {
  InterceptlySettings get settings;
  InspectorPreferences get preferences;

  List<RequestSummary> get entries;
  RequestFilter get filter;
  bool get isEnabled;
  int get droppedCount;
  NetworkSimulationProfile get networkSimulation;

  String? get masterQuery;
  bool get isMasterSearchActive;
  bool get isScanningBodies;
  bool get isScanningFiles;
  bool get groupingEnabled;

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
}
