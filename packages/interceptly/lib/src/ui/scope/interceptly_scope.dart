import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../engine/interceptly_engine.dart';
import '../search/master_search_controller.dart';
import '../../model/domain_group.dart';
import '../../model/index_entry.dart';
import '../../model/interceptly_settings.dart';
import '../../model/network_simulation.dart';
import '../../model/realtime_frame.dart';
import '../../model/realtime_protocol_type.dart';
import '../../model/request_filter.dart';
import '../../model/request_record.dart';
import '../../model/request_summary.dart';
import '../../model/search_match_scope.dart';
import '../settings/inspector_preferences.dart';
import 'grouping_controller.dart';

/// Presentation state controller managing UI-level filtering, search, and grouping
/// on top of an [InterceptlyEngine].
@internal
class InterceptlyScopeController extends ChangeNotifier {
  /// Creates a UI scope controller backed by [engine] and optional [preferences].
  InterceptlyScopeController({
    InterceptlyEngine? engine,
    InterceptlyPreferences? preferences,
  })  : engine = engine ?? InterceptlyEngine.instance,
        _preferences = preferences ?? InterceptlyPreferences.shared,
        _ownsPreferences = preferences != null {
    if (preferences == null) {
      _preferences.setUrlDecodeEnabled(this.engine.settings.urlDecodeEnabled);
    }
    this.engine.addListener(_onEngineUpdated);
    _search.addListener(_onSearchUpdated);
    _grouping.addListener(_onGroupingUpdated);
    _preferences.addListener(_onPreferencesUpdated);
  }

  /// The underlying headless data engine.
  final InterceptlyEngine engine;

  final MasterSearchController _search = MasterSearchController();
  final GroupingController _grouping = GroupingController();
  final InterceptlyPreferences _preferences;
  final bool _ownsPreferences;

  RequestFilter _filter = RequestFilter();
  Set<String>? _cachedAvailableDomains;
  List<DomainGroup>? _cachedGroupedRecords;
  int _cacheVersion = 0;
  int _lastComputedCacheVersion = -1;
  int _lastReconciledEntriesVersion = -1;
  bool _isDisposed = false;

  InterceptlyPreferences get preferences => _preferences;
  RequestFilter get filter => _filter;
  InterceptlySettings get settings => engine.settings;
  bool get isEnabled => engine.isEnabled;
  int get droppedCount => engine.droppedCount;
  NetworkSimulationProfile get networkSimulation => engine.networkSimulation;
  int get entriesVersion => engine.entriesVersion;
  bool get isRealtimeActive => engine.isRealtimeActive;

  String? get masterQuery => _search.query;
  bool get isMasterSearchActive => _search.isActive;
  bool get isScanningBodies => _search.isScanningBodies;
  bool get isScanningFiles => _search.isScanningFiles;
  bool get groupingEnabled => _grouping.enabled;

  /// Returns filtered entries based on active search and filters.
  List<RequestSummary> get entries {
    final baseList = _search.isActive
        ? (_search.results ?? const <IndexEntry>[])
        : engine.entries;
    if (_filter.isEmpty) {
      return baseList.cast<RequestSummary>();
    }
    return baseList.where(_filter.matches).toList().cast<RequestSummary>();
  }

  /// Available domains present in the current entries.
  Set<String> get availableDomains {
    return _cachedAvailableDomains ??= engine.entries
        .map((entry) => RequestFilter.extractDomain(entry.url))
        .toSet();
  }

  Set<SearchMatchScope> getSearchScopes(String id) => _search.getScopes(id);

  RequestSummary? byId(String id) => engine.byId(id);

  Future<RequestRecord> loadDetailById(String id) => engine.loadDetailById(id);

  Future<RequestRecord> loadDetail(RequestSummary summary) =>
      engine.loadDetail(summary);

  void applyFilter(RequestFilter filter) {
    if (_filter == filter) return;
    _filter = filter;
    _invalidateGroupedCache();
    notifyListeners();
  }

  void clearFilter() {
    _filter = RequestFilter();
    _invalidateGroupedCache();
    notifyListeners();
  }

  void toggleGrouping(bool enabled) {
    _grouping.setEnabled(enabled);
  }

  void toggleDomainExpanded(String domain) {
    _grouping.toggleDomainExpanded(domain);
  }

  List<DomainGroup> getGroupedRecords() {
    if (_cachedGroupedRecords != null &&
        _lastComputedCacheVersion == _cacheVersion) {
      return _cachedGroupedRecords!;
    }
    final currentEntries = entries;
    final grouped = <String, List<RequestSummary>>{};
    for (final entry in currentEntries) {
      final domain = RequestFilter.extractDomain(entry.url);
      grouped.putIfAbsent(domain, () => []).add(entry);
    }
    _cachedGroupedRecords = grouped.entries
        .map(
          (e) => DomainGroup(
            domain: e.key,
            requests: e.value,
            isExpanded: _grouping.isExpanded(e.key),
          ),
        )
        .toList();
    _lastComputedCacheVersion = _cacheVersion;
    return _cachedGroupedRecords!;
  }

  void cancelMasterSearch() {
    _lastReconciledEntriesVersion = -1;
    _search.cancel();
  }

  Future<void> startMasterSearch(String query) {
    _lastReconciledEntriesVersion = engine.entriesVersion;
    return _search.start(
      query: query,
      allEntries: engine.entries.cast<IndexEntry>(),
      filePath: engine.tempFilePath,
      currentFileRotationCount: engine.fileRotationCount,
    );
  }

  void setNetworkSimulation(NetworkSimulationProfile profile) =>
      engine.setNetworkSimulation(profile);

  void clearNetworkSimulation() => engine.clearNetworkSimulation();

  Future<void> clear() async {
    _lastReconciledEntriesVersion = -1;
    _filter = RequestFilter();
    _search.reset();
    _invalidateGroupedCache();
    await engine.clear();
    notifyListeners();
  }

  Future<void> clearRest() async {
    _lastReconciledEntriesVersion = -1;
    _filter = RequestFilter();
    _search.reset();
    _invalidateGroupedCache();
    await engine.clearRest();
    notifyListeners();
  }

  Future<void> clearRealtime() async {
    _invalidateGroupedCache();
    await engine.clearRealtime();
    notifyListeners();
  }

  List<RealtimeFrame> getRealtimeFrames(String sessionId) =>
      engine.getRealtimeFrames(sessionId);

  RealtimeFrameCounts getRealtimeFrameCounts(String sessionId) =>
      engine.getRealtimeFrameCounts(sessionId);

  ValueListenable<RealtimeFrameCounts> getRealtimeFrameCountsNotifier(
    String sessionId,
  ) =>
      engine.getRealtimeFrameCountsNotifier(sessionId);

  bool canSendRealtimeMessage(String sessionId) =>
      engine.canSendRealtimeMessage(sessionId);

  RealtimeProtocolType? getRealtimeProtocol(String sessionId) =>
      engine.getRealtimeProtocol(sessionId);

  Future<void> sendRealtimeMessage(
    String sessionId,
    RealtimeMessageDraft draft,
  ) =>
      engine.sendRealtimeMessage(sessionId, draft);

  Future<dynamic> loadRealtimePayload(RealtimeFrame frame) =>
      engine.loadRealtimePayload(frame);

  void _onEngineUpdated() {
    _invalidateGroupedCache();
    if (_search.isActive) {
      final currentVersion = engine.entriesVersion;
      if (_lastReconciledEntriesVersion != currentVersion) {
        _lastReconciledEntriesVersion = currentVersion;
        final changed = engine.recentChangedEntries;
        if (changed.isNotEmpty) {
          for (final e in changed) {
            _search.updateOrAddEntry(e);
          }
        } else {
          for (final e in engine.entries) {
            if (e is IndexEntry) {
              _search.updateOrAddEntry(e);
            }
          }
        }
        final validIds = {for (final e in engine.entries) e.id};
        _search.pruneMissing(validIds);
      }
    }
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void _onSearchUpdated() {
    _invalidateGroupedCache();
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void _onGroupingUpdated() {
    _invalidateGroupedCache();
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void _onPreferencesUpdated() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void _invalidateGroupedCache() {
    _cachedGroupedRecords = null;
    _cacheVersion++;
    _cachedAvailableDomains = null;
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    engine.removeListener(_onEngineUpdated);
    _search.removeListener(_onSearchUpdated);
    _search.dispose();
    _grouping.removeListener(_onGroupingUpdated);
    _grouping.dispose();
    _preferences.removeListener(_onPreferencesUpdated);
    if (_ownsPreferences) {
      _preferences.dispose();
    }
    super.dispose();
  }
}

/// Provides [InterceptlyScopeController] down the widget tree using [InheritedNotifier].
@internal
class InterceptlyScope extends InheritedNotifier<InterceptlyScopeController> {
  /// Wraps [child] with an [InterceptlyScopeController].
  const InterceptlyScope({
    super.key,
    required InterceptlyScopeController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Retrieves the [InterceptlyScopeController] from [context], registering it for rebuilds.
  static InterceptlyScopeController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<InterceptlyScope>();
    assert(
      scope != null,
      'No InterceptlyScope found in context. Wrap your widget tree with InterceptlyScope.',
    );
    return scope!.notifier!;
  }

  /// Retrieves the [InterceptlyScopeController] from [context] if present, registering it for rebuilds.
  static InterceptlyScopeController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<InterceptlyScope>()
        ?.notifier;
  }

  /// Retrieves the [InterceptlyScopeController] from [context] without registering for rebuilds.
  static InterceptlyScopeController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<InterceptlyScope>();
    assert(
      scope != null,
      'No InterceptlyScope found in context. Wrap your widget tree with InterceptlyScope.',
    );
    return scope!.notifier!;
  }

  /// Retrieves the [InterceptlyScopeController] from [context] without registering for rebuilds, or null if absent.
  static InterceptlyScopeController? maybeRead(BuildContext context) {
    return context.getInheritedWidgetOfExactType<InterceptlyScope>()?.notifier;
  }
}
