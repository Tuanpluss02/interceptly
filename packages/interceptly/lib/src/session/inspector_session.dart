import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../model/body_location.dart';

import '../adapter/realtime_traffic_collector.dart';
import '../core/interceptly_controller.dart';
import '../model/domain_group.dart';
import '../model/index_entry.dart';
import '../model/interceptly_settings.dart';
import '../model/network_simulation.dart';
import '../model/raw_capture.dart';
import '../model/realtime_frame.dart';
import '../model/realtime_protocol_type.dart';
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
import 'realtime_body_store.dart';
import 'realtime_store.dart';
import 'writer_isolate.dart';

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
      maxTotalRealtimeFrames: _settings.maxTotalRealtimeFrames,
      onThrottledBatch: notifyListeners,
    );
    _realtimeBodyStore = RealtimeBodyStore();
    _detailLoader = DetailLoader(
      memoryIndex: _memoryIndex,
      tempFilePathProvider: () => _capturePipeline.tempFilePath,
      maxUiPreviewBytesProvider: () => _settings.maxUiPreviewBytes,
    );
    _search.addListener(_onSearchChanged);
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


  static InspectorSession? _instance;

  /// Returns the shared default session singleton.
  static InspectorSession get instance =>
      _instance ??= InspectorSession(settings: _defaultSettings);

  /// Resets the singleton instance and configuration for isolated unit/widget tests.
  @visibleForTesting
  static Future<void> resetForTesting() async {
    await _instance?.dispose();
    _instance = null;
    _defaultSettings = const InterceptlySettings();
    // ignore: invalid_use_of_visible_for_testing_member
    Interceptly.resetForTesting();
  }

  /// Unique ID for this session instance to isolate temporary files.
  final String sessionId;

  InterceptlySettings _settings;
  late final MemoryIndex _memoryIndex;
  late final CapturePipeline _capturePipeline;
  late final PendingTracker _pendingTracker;
  late final RealtimeStore _realtimeStore;
  late final RealtimeBodyStore _realtimeBodyStore;
  late final DetailLoader _detailLoader;
  String? _realtimeDirPath;
  Future<void>? _realtimeBodyStoreInitFuture;

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

  bool _realtimeExplicitlyEnabled = false;

  @override
  bool get isRealtimeActive {
    if (_settings.enableRealtime != null) {
      return _settings.enableRealtime!;
    }
    return _realtimeExplicitlyEnabled ||
        _memoryIndex.entries.any((e) => e.isRealtime);
  }

  /// Explicitly marks realtime capability as active and notifies listeners.
  void markRealtimeActive() {
    if (!_realtimeExplicitlyEnabled) {
      _realtimeExplicitlyEnabled = true;
      notifyListeners();
    }
  }

  @override
  Set<SearchMatchScope> getSearchScopes(String id) => _search.getScopes(id);

  @override
  List<RequestSummary> get entries {
    final baseList = _search.isActive
        ? (_search.results ?? const <IndexEntry>[])
        : _memoryIndex.entries;
    if (_filter.isEmpty) {
      return baseList.cast<RequestSummary>();
    }
    return baseList.where(_filter.matches).toList().cast<RequestSummary>();
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
    _realtimeStore.updateGlobalCapacity(
      maxTotalFrames: newSettings.maxTotalRealtimeFrames,
    );
    _memoryIndex.updateMaxEntries(newSettings.maxEntries);
    _preferences.setUrlDecodeEnabled(newSettings.urlDecodeEnabled);
    notifyListeners();
  }

  /// Configures settings for this specific session instance.
  void configureSession(InterceptlySettings newSettings) =>
      _applySettings(newSettings);

  /// Initializes background workers and disk storage.
  Future<void> initialize() => _capturePipeline.initialize();

  Future<void> _ensureRealtimeBodyStoreInitialized() {
    if (_realtimeBodyStore.isInitialized || _isDisposed) {
      return Future<void>.value();
    }
    return _realtimeBodyStoreInitFuture ??= _performRealtimeBodyStoreInit();
  }

  Future<void> _performRealtimeBodyStoreInit() async {
    if (_realtimeBodyStore.isInitialized || _isDisposed) return;
    String dirPath;
    if (_settings.persistToDisk) {
      try {
        final dir = await getTemporaryDirectory();
        dirPath = dir.path;
      } catch (_) {
        dirPath = Directory.systemTemp.path;
      }
    } else {
      dirPath = Directory.systemTemp.path;
    }
    _realtimeDirPath = dirPath;
    await _realtimeBodyStore.initForWrite(
      dirPath,
      fileName: 'interceptly_${sessionId}_realtime.tmp',
    );
  }

  void _onGroupingChanged() {
    _invalidateGroupedCache();
    notifyListeners();
  }

  void _onSearchChanged() {
    _invalidateGroupedCache();
    notifyListeners();
  }

  void _onCaptureReady(IndexEntry entry) {
    _entriesVersion++;
    _memoryIndex.add(entry);
    _invalidateGroupedCache();
    _search.updateOrAddEntry(entry);
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

  /// Access to the underlying capture pipeline for testing.
  @visibleForTesting
  CapturePipeline get capturePipeline => _capturePipeline;

  /// Access to the underlying writer isolate for testing.
  @visibleForTesting
  WriterIsolate get writerIsolate => _capturePipeline.writerIsolate;

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
    if (_isDisposed || _enabled) return;
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
    _recordPendingEntry(
      id: id,
      method: method,
      url: url,
      timestamp: timestamp,
      requestHeaders: requestHeaders,
      requestBodyBytes: requestBodyBytes,
      requestContentType: requestContentType,
    );
  }

  void _recordPendingEntry({
    required String id,
    required String method,
    required String url,
    required DateTime timestamp,
    Map<String, String> requestHeaders = const {},
    Uint8List? requestBodyBytes,
    String? requestContentType,
  }) {
    _entriesVersion++;
    final pending = _pendingTracker.recordPending(
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
    _search.updateOrAddEntry(pending);
    _scheduleCoalescedNotify();
  }

  /// Records a captured [RealtimeFrame] into the session buffer.
  ///
  /// If the frame exceeds [InterceptlySettings.realtimeBodyOffloadThreshold]
  /// and disk persistence is enabled, it is appended to [RealtimeBodyStore]
  /// and swapped with an offloaded [RealtimeFrame] in-place.
  Future<void> recordRealtimeFrame(RealtimeFrame frame) {
    if (!_enabled || _isDisposed) return Future<void>.value();
    final predicate = _settings.shouldCapture;
    if (predicate != null) {
      final entry = _memoryIndex.byId(frame.sessionId);
      if (entry == null) return Future<void>.value();
    }

    if (_settings.persistToDisk &&
        frame.location == BodyLocation.memory &&
        frame.payloadSizeBytes >= _settings.realtimeBodyOffloadThreshold) {
      _realtimeStore.recordFrame(frame);
      return _offloadAndReplaceFrame(frame);
    } else {
      _realtimeStore.recordFrame(frame);
      return Future<void>.value();
    }
  }

  Future<void> _offloadAndReplaceFrame(RealtimeFrame frame) async {
    await _ensureRealtimeBodyStoreInitialized();
    final Uint8List bytes = frame.preEncodedBytes ??
        (frame.type == FrameType.text
            ? Uint8List.fromList(utf8.encode(frame.textPayload ?? ''))
            : frame.binaryPayload ?? Uint8List(0));

    final (offset, length, rotation) = await _realtimeBodyStore.append(bytes);

    final offloaded = RealtimeFrame.offloaded(
      id: frame.id,
      sessionId: frame.sessionId,
      direction: frame.direction,
      timestamp: frame.timestamp,
      type: frame.type,
      payloadSizeBytes: frame.payloadSizeBytes,
      shortPreview: frame.shortPreview,
      fileOffset: offset,
      fileLength: length,
      rotationCount: rotation,
      eventName: frame.eventName,
    );

    _realtimeStore.replaceFrame(offloaded);
  }

  @override
  Future<dynamic> loadRealtimePayload(RealtimeFrame frame) async {
    if (frame.location == BodyLocation.memory) {
      if (frame.type == FrameType.text) {
        return frame.textPayload ?? '';
      }
      return frame.binaryPayload ?? Uint8List(0);
    }

    if (frame.rotationCount != null &&
        frame.rotationCount! < _realtimeBodyStore.rotationCount) {
      return '[Payload expired due to file rotation]';
    }

    if (!_realtimeBodyStore.isInitialized) {
      return '[Payload unavailable: store uninitialized]';
    }

    final offset = frame.fileOffset;
    final length = frame.fileLength;
    if (offset == null || length == null || length <= 0) {
      return frame.type == FrameType.text ? '' : Uint8List(0);
    }

    try {
      final bytes = await _realtimeBodyStore.readBytes(offset, length);
      if (frame.type == FrameType.text) {
        return utf8.decode(bytes, allowMalformed: true);
      }
      return bytes;
    } catch (e) {
      return '[Error loading payload: $e]';
    }
  }

  @override
  List<RealtimeFrame> getRealtimeFrames(String sessionId) =>
      _realtimeStore.getRealtimeFrames(sessionId);

  @override
  RealtimeFrameCounts getRealtimeFrameCounts(String sessionId) =>
      _realtimeStore.getFrameCounts(sessionId);

  @override
  bool canSendRealtimeMessage(String sessionId) =>
      RealtimeTrafficCollector.instance.canSend(sessionId);

  @override
  RealtimeProtocolType? getRealtimeProtocol(String sessionId) =>
      RealtimeTrafficCollector.instance.getSender(sessionId)?.protocolType;

  @override
  Future<void> sendRealtimeMessage(
    String sessionId,
    RealtimeMessageDraft draft,
  ) =>
      RealtimeTrafficCollector.instance.sendMessage(sessionId, draft);

  /// Records opening of a realtime connection.
  void recordRealtimeConnection({
    required String id,
    required String url,
    Map<String, String> headers = const {},
    DateTime? timestamp,
    bool isPreValidated = false,
    RealtimeProtocolType protocolType = RealtimeProtocolType.webSocket,
  }) {
    if (!_enabled || _isDisposed) return;
    if (!isPreValidated &&
        _settings.shouldCapture != null &&
        !_settings.shouldCapture!(url)) {
      return;
    }
    markRealtimeActive();
    final method = switch (protocolType) {
      RealtimeProtocolType.webSocket => 'WS',
      RealtimeProtocolType.socketIo => 'SIO',
      RealtimeProtocolType.sse => 'SSE',
    };
    _recordPendingEntry(
      id: id,
      method: method,
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
    _realtimeStore.markSessionClosed(id);
    _invalidateGroupedCache();
    notifyListeners();
  }

  @override
  ValueListenable<RealtimeFrameCounts> getRealtimeFrameCountsNotifier(
    String sessionId,
  ) =>
      _realtimeStore.getFrameCountsNotifier(sessionId);

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
      if (_realtimeBodyStore.isInitialized && _realtimeDirPath != null) {
        await _realtimeBodyStore.resetFile(_realtimeDirPath!);
      }
      _realtimeBodyStoreInitFuture = null;
    } finally {
      _clearFuture = null;
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      throw StateError('InspectorSession has already been disposed.');
    }
    _isDisposed = true;
    if (identical(_instance, this)) {
      _instance = null;
    }
    _realtimeBodyStoreInitFuture = null;
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
    await _realtimeBodyStore.dispose();
    super.dispose();
  }

  /// Forces file rotation on the session's [RealtimeBodyStore] for testing.
  @visibleForTesting
  Future<void> rotateRealtimeBodyStoreForTesting() =>
      _realtimeBodyStore.rotate();

  /// Current byte offset in [RealtimeBodyStore] for testing.
  @visibleForTesting
  int get realtimeBodyStoreCurrentOffsetForTesting =>
      _realtimeBodyStore.currentOffset;

  /// Underlying [RealtimeBodyStore] for testing.
  @visibleForTesting
  RealtimeBodyStore get realtimeBodyStoreForTesting => _realtimeBodyStore;

  /// Total count of realtime frames currently retained across all sessions for testing.
  @visibleForTesting
  int get totalRealtimeFramesForTesting =>
      _realtimeStore.totalFramesAcrossSessions;

  /// Flushes pending operations in [RealtimeBodyStore] for testing.
  @visibleForTesting
  Future<void> flushRealtimeBodyStoreForTesting() =>
      // ignore: invalid_use_of_visible_for_testing_member
      _realtimeBodyStore.flushForTesting();
}
