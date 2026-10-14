import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/domain_group.dart';
import '../model/index_entry.dart';
import '../model/interceptly_settings.dart';
import '../model/network_simulation.dart';
import '../model/raw_capture.dart';
import '../model/realtime_frame.dart';
import '../model/request_filter.dart';
import '../model/request_record.dart';
import '../model/request_summary.dart';
import '../model/search_match_scope.dart';
import '../simulation/network_simulation_service.dart';
import 'capture_pipeline.dart';
import 'detail_loader.dart';
import 'grouping_controller.dart';
import 'inspector_preferences.dart';
import 'inspector_session_view.dart';
import 'master_search_controller.dart';
import 'memory_index.dart';
import 'pending_tracker.dart';
import 'realtime_store.dart';

/// Central lifecycle facade for an Interceptly inspection session.
///
/// Composes [CapturePipeline], [PendingTracker], [RealtimeStore], [DetailLoader],
/// and [MemoryIndex] to provide a unified entry point.
class InspectorSession extends ChangeNotifier implements InspectorSessionView {
  /// Creates an inspector session configured with [settings].
  InspectorSession({InterceptlySettings? settings})
      : _settings = settings ?? _defaultSettings,
        sessionId = _generateSessionId() {
    _memoryIndex = MemoryIndex(maxEntries: _settings.maxEntries);
    _pendingTracker = PendingTracker(
      timeoutDuration: _settings.pendingTimeout,
      memoryIndex: _memoryIndex,
      onTimeout: _onPendingTimeout,
    );
    _capturePipeline = CapturePipeline(
      settings: _settings,
      sessionId: sessionId,
      onEntryReady: _onCaptureReady,
      onEntryReceived: _pendingTracker.cancel,
    );
    _realtimeStore = RealtimeStore(
      maxFramesPerSession: _settings.maxFramesPerSession,
      onThrottledBatch: notifyListeners,
    );
    _detailLoader = DetailLoader(
      memoryIndex: _memoryIndex,
      tempFilePathProvider: () => _capturePipeline.tempFilePath,
      maxUiPreviewBytesProvider: () => _settings.maxUiPreviewBytes,
    );
    _search.addListener(notifyListeners);
    _grouping.addListener(_onGroupingChanged);
    _preferences.addListener(notifyListeners);
  }

  static InterceptlySettings _defaultSettings = const InterceptlySettings();
  static int _sessionCounter = 0;

  static String _generateSessionId() {
    final seq = ++_sessionCounter;
    final time = DateTime.now().microsecondsSinceEpoch;
    return '${time}_$seq';
  }

  /// Global configure helper for the shared singleton before or after first access.
  static void configure(InterceptlySettings settings) {
    _defaultSettings = settings;
    _instance?._applySettings(settings);
  }

  static InspectorSession? _instance;

  /// Returns the shared default session singleton.
  static InspectorSession get instance =>
      _instance ??= InspectorSession(settings: _defaultSettings);

  /// Unique ID for this session instance to isolate temporary files.
  final String sessionId;

  InterceptlySettings _settings;
  late final MemoryIndex _memoryIndex;
  late final CapturePipeline _capturePipeline;
  late final PendingTracker _pendingTracker;
  late final RealtimeStore _realtimeStore;
  late final DetailLoader _detailLoader;

  final InspectorPreferences _preferences = InspectorPreferences();
  final MasterSearchController _search = MasterSearchController();
  final GroupingController _grouping = GroupingController();

  RequestFilter _filter = RequestFilter();
  NetworkSimulationProfile _networkSimulation = NetworkSimulationProfile.none;
  Future<void>? _clearFuture;
  bool _enabled = true;
  bool _isDisposed = false;

  Set<String>? _cachedAvailableDomains;
  List<DomainGroup>? _cachedGroupedRecords;
  int _cacheVersion = 0;
  int _lastComputedCacheVersion = -1;
  int _entriesVersion = 0;
  Timer? _coalesceNotifyTimer;
  bool _hasPendingCoalescedNotify = false;

  @override
  InterceptlySettings get settings => _settings;

  /// Whether this session has been disposed.
  bool get isDisposed => _isDisposed;

  @override
  int get entriesVersion => _entriesVersion;

  @override
  bool get isEnabled => _enabled;

  @override
  int get droppedCount => _capturePipeline.droppedCount;

  @override
  InspectorPreferences get preferences => _preferences;

  @override
  NetworkSimulationProfile get networkSimulation => _networkSimulation;

  @override
  RequestFilter get filter => _filter;

  int get totalEntries => _memoryIndex.length;

  @override
  String? get masterQuery => _search.query;

  @override
  bool get isMasterSearchActive => _search.isActive;

  @override
  bool get isScanningBodies => _search.isScanningBodies;

  @override
  bool get isScanningFiles => _search.isScanningFiles;

  @override
  bool get groupingEnabled => _grouping.enabled;

  @override
  Set<SearchMatchScope> getSearchScopes(String id) => _search.getScopes(id);

  @override
  List<RequestSummary> get entries {
    if (_search.isActive) {
      return (_search.results ?? const <IndexEntry>[]).cast<RequestSummary>();
    }
    return _memoryIndex.filtered(_filter).cast<RequestSummary>();
  }

  @override
  Set<String> get availableDomains {
    return _cachedAvailableDomains ??= _memoryIndex.entries
        .map((entry) => RequestFilter.extractDomain(entry.url))
        .toSet();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  void _applySettings(InterceptlySettings newSettings) {
    _settings = newSettings;
    _capturePipeline.updateSettings(newSettings);
    _pendingTracker.updateTimeout(newSettings.pendingTimeout);
    _realtimeStore.updateMaxFramesPerSession(newSettings.maxFramesPerSession);
    _memoryIndex.updateMaxEntries(newSettings.maxEntries);
    _preferences.setUrlDecodeEnabled(newSettings.urlDecodeEnabled);
    notifyListeners();
  }

  /// Configures settings for this specific session instance.
  void configureSession(InterceptlySettings newSettings) =>
      _applySettings(newSettings);

  /// Initializes background workers and disk storage.
  Future<void> initialize() => _capturePipeline.initialize();

  void _onGroupingChanged() {
    _invalidateGroupedCache();
    notifyListeners();
  }

  void _onCaptureReady(IndexEntry entry) {
    _entriesVersion++;
    _memoryIndex.add(entry);
    _invalidateGroupedCache();
    _scheduleCoalescedNotify();
  }

  void _scheduleCoalescedNotify() {
    if (_isDisposed) return;
    _hasPendingCoalescedNotify = true;
    _coalesceNotifyTimer ??= Timer(const Duration(milliseconds: 60), () {
      _coalesceNotifyTimer = null;
      if (_hasPendingCoalescedNotify && !_isDisposed) {
        _hasPendingCoalescedNotify = false;
        notifyListeners();
      }
    });
  }

  /// Immediately flushes any scheduled coalesced notifications.
  void flushPendingNotifications() {
    if (_coalesceNotifyTimer != null) {
      _coalesceNotifyTimer?.cancel();
      _coalesceNotifyTimer = null;
      if (_hasPendingCoalescedNotify && !_isDisposed) {
        _hasPendingCoalescedNotify = false;
        notifyListeners();
      }
    }
  }

  /// Manually dispatches an incoming [entry] through the ingestion pipeline for testing.
  @visibleForTesting
  void handleEntryReadyForTesting(IndexEntry entry) => _onCaptureReady(entry);

  void _onPendingTimeout(IndexEntry timedOutEntry) {
    _entriesVersion++;
    _invalidateGroupedCache();
    notifyListeners();
  }

  void _invalidateGroupedCache() {
    _cachedGroupedRecords = null;
    _cacheVersion++;
    _cachedAvailableDomains = null;
  }

  /// Enables traffic capture.
  @override
  void enable() {
    if (_enabled) return;
    _enabled = true;
    notifyListeners();
  }

  /// Disables traffic capture, dropping new captures silently.
  @override
  void disable() {
    if (!_enabled) return;
    _enabled = false;
    notifyListeners();
  }

  @override
  void setNetworkSimulation(NetworkSimulationProfile profile) {
    _networkSimulation = profile;
    notifyListeners();
  }

  @override
  void clearNetworkSimulation() {
    if (_networkSimulation.isNoThrottling) return;
    _networkSimulation = NetworkSimulationProfile.none;
    notifyListeners();
  }

  @override
  void toggleGrouping(bool enabled) {
    _grouping.setEnabled(enabled);
    _invalidateGroupedCache();
  }

  @override
  void toggleDomainExpanded(String domain) {
    _grouping.toggleDomainExpanded(domain);
    _invalidateGroupedCache();
  }

  @override
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

  /// Applies simulated upload network latency and bandwidth throttling.
  Future<void> applyNetworkSimulationBeforeRequest({required int uploadBytes}) =>
      NetworkSimulationService.applyBeforeRequest(
        _networkSimulation,
        uploadBytes: uploadBytes,
      );

  /// Applies simulated download network latency and bandwidth throttling.
  Future<void> applyNetworkSimulationAfterResponse(
          {required int downloadBytes}) =>
      NetworkSimulationService.applyAfterResponse(
        _networkSimulation,
        downloadBytes: downloadBytes,
      );

  /// Computes simulated throughput delay for streaming [chunkBytes].
  Duration throughputDelayForChunk(int chunkBytes) =>
      NetworkSimulationService.throughputDelayForChunk(
        _networkSimulation,
        chunkBytes,
      );

  /// Enqueues [capture] for asynchronous background processing.
  void record(RawCapture capture) {
    if (!_enabled) return;
    if (_settings.shouldCapture != null &&
        !_settings.shouldCapture!(capture.url)) {
      return;
    }
    _capturePipeline.record(capture);
  }

  /// Inserts an immediate pending request entry before response completion.
  void recordPending({
    required String id,
    required String method,
    required String url,
    required DateTime timestamp,
    Map<String, String> requestHeaders = const {},
    Uint8List? requestBodyBytes,
    String? requestContentType,
  }) {
    if (!_enabled) return;
    if (_settings.shouldCapture != null && !_settings.shouldCapture!(url)) {
      return;
    }
    _entriesVersion++;
    _pendingTracker.recordPending(
      id: id,
      method: method,
      url: url,
      timestamp: timestamp,
      requestHeaders: requestHeaders,
      requestBodyBytes: requestBodyBytes,
      requestContentType: requestContentType,
      settings: _settings,
    );
    _invalidateGroupedCache();
    notifyListeners();
  }

  /// Records a captured realtime frame into the session buffer.
  ///
  /// Frames belonging to connections rejected by [InterceptlySettings.shouldCapture]
  /// are skipped, resolving the connection URL from the stored handshake entry.
  /// Unknown session ids are skipped only while a capture predicate is active.
  void recordRealtimeFrame(RealtimeFrame frame) {
    if (!_enabled || _isDisposed) return;
    final predicate = _settings.shouldCapture;
    if (predicate != null) {
      final String? url = _memoryIndex.byId(frame.sessionId)?.url;
      if (url == null || !predicate(url)) return;
    }
    _realtimeStore.recordFrame(frame);
  }

  @override
  List<RealtimeFrame> getRealtimeFrames(String sessionId) =>
      _realtimeStore.getFrames(sessionId);

  @override
  List<RealtimeFrame> getFrames(String sessionId) =>
      getRealtimeFrames(sessionId);

  /// Records opening of a realtime connection.
  void recordRealtimeConnection({
    required String id,
    required String url,
    Map<String, String> headers = const {},
    DateTime? timestamp,
  }) {
    if (!_enabled || _isDisposed) return;
    recordPending(
      id: id,
      method: 'WS',
      url: url,
      timestamp: timestamp ?? DateTime.now(),
      requestHeaders: headers,
    );
  }

  /// Records closing of an active realtime connection with close code and reason.
  void closeRealtimeConnection(
    String id, {
    int closeCode = 1000,
    String? closeReason,
  }) {
    if (_isDisposed) return;
    _entriesVersion++;
    _pendingTracker.closeRealtimeConnection(
      id,
      closeCode: closeCode,
      closeReason: closeReason,
    );
    _invalidateGroupedCache();
    notifyListeners();
  }

  @override
  void applyFilter(RequestFilter filter) {
    if (_filter == filter) return;
    _filter = filter;
    _invalidateGroupedCache();
    notifyListeners();
  }

  @override
  void clearFilter() {
    _filter = RequestFilter();
    _invalidateGroupedCache();
    notifyListeners();
  }

  @override
  void cancelMasterSearch() => _search.cancel();

  @override
  Future<void> startMasterSearch(String query) => _search.start(
        query: query,
        allEntries: _memoryIndex.entries,
        filePath: _capturePipeline.tempFilePath,
      );

  /// Looks up an entry by its unique [id] in O(1) time.
  @override
  RequestSummary? byId(String id) => _memoryIndex.byId(id);

  /// Loads the full request record by request [id].
  @override
  Future<RequestRecord> loadDetailById(String id) =>
      _detailLoader.loadDetailById(id);

  /// Loads full details for [summary].
  @override
  Future<RequestRecord> loadDetail(RequestSummary summary) {
    if (summary is IndexEntry) {
      return _detailLoader.loadDetailByEntry(summary);
    }
    return loadDetailById(summary.id);
  }

  @override
  Future<void> clear() async {
    if (_clearFuture != null) return _clearFuture!;
    return _clearFuture = _performClear();
  }

  Future<void> _performClear() async {
    try {
      _coalesceNotifyTimer?.cancel();
      _coalesceNotifyTimer = null;
      _hasPendingCoalescedNotify = false;
      _entriesVersion++;
      if (_capturePipeline.isInitialized) {
        await _capturePipeline.clear();
      } else {
        _capturePipeline.clearSync();
      }
      _memoryIndex.clear();
      _pendingTracker.clear();
      _realtimeStore.clear();
      _invalidateGroupedCache();
      _filter = RequestFilter();
      _search.reset();
      if (!_isDisposed) {
        notifyListeners();
      }
    } finally {
      _clearFuture = null;
    }
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    _coalesceNotifyTimer?.cancel();
    _coalesceNotifyTimer = null;
    _hasPendingCoalescedNotify = false;
    _enabled = false;
    _realtimeStore.dispose();
    _pendingTracker.dispose();
    _memoryIndex.clear();
    _search.cancel();
    _search.dispose();
    _grouping.removeListener(_onGroupingChanged);
    _grouping.dispose();
    _preferences.removeListener(notifyListeners);
    _preferences.dispose();
    await _capturePipeline.dispose();
    if (identical(_instance, this)) {
      _instance = null;
    }
    super.dispose();
  }
}
