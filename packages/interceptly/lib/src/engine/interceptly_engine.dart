import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../adapter/realtime_traffic_collector.dart';
import '../model/body_location.dart';
import '../model/index_entry.dart';
import '../model/interceptly_settings.dart';
import '../model/network_simulation.dart';
import '../model/raw_capture.dart';
import '../model/realtime_frame.dart';
import '../model/realtime_protocol_type.dart';
import '../model/request_record.dart';
import '../model/request_summary.dart';
import '../model/search_match_scope.dart';
import '../model/search_result.dart';
import '../simulation/network_simulation_service.dart';
import 'body_store.dart';
import 'capture_pipeline.dart';
import 'detail_loader.dart';
import 'memory_index.dart';
import 'pending_tracker.dart';
import 'realtime_store.dart';
import 'search_matcher.dart';

/// Central headless data engine for Interceptly.
///
/// Orchestrates [CapturePipeline], [PendingTracker], [RealtimeStore], [DetailLoader],
/// and [MemoryIndex] to provide asynchronous capture ingestion and hybrid storage.
///
/// This engine is internal to the Interceptly package and should not be accessed directly
/// by app developers or satellite adapters.
@internal
class InterceptlyEngine extends ChangeNotifier {
  /// Creates an interceptly engine configured with [settings].
  InterceptlyEngine({InterceptlySettings? settings})
      : _settings = settings ?? _defaultSettings,
        engineId = _generateEngineId() {
    _memoryIndex = MemoryIndex(maxEntries: _settings.maxEntries);
    _pendingTracker = PendingTracker(
      timeoutDuration: _settings.pendingTimeout,
      memoryIndex: _memoryIndex,
      onTimeout: _onPendingTimeout,
    );
    _capturePipeline = CapturePipeline(
      settings: _settings,
      sessionId: engineId,
      onEntryReady: _onCaptureReady,
      onEntryReceived: _pendingTracker.cancel,
    );
    _realtimeStore = RealtimeStore(
      maxFramesPerSession: _settings.maxFramesPerSession,
      maxTotalRealtimeFrames: _settings.maxTotalRealtimeFrames,
      onThrottledBatch: notifyListeners,
    );
    _detailLoader = DetailLoader(
      memoryIndex: _memoryIndex,
      tempFilePathProvider: () => _capturePipeline.tempFilePath,
      maxUiPreviewBytesProvider: () => _settings.maxUiPreviewBytes,
      fileRotationCountProvider: () => _capturePipeline.fileRotationCount,
    );
  }

  static InterceptlySettings _defaultSettings = const InterceptlySettings();
  static int _engineCounter = 0;

  static String _generateEngineId() {
    final seq = ++_engineCounter;
    final time = DateTime.now().microsecondsSinceEpoch;
    return '${time}_$seq';
  }

  static InterceptlyEngine? _instance;

  /// Returns the shared default engine singleton.
  static InterceptlyEngine get instance =>
      _instance ??= InterceptlyEngine(settings: _defaultSettings);

  /// Resets the singleton instance and configuration for isolated unit/widget tests.
  static Future<void> resetForTesting() async {
    await _instance?.dispose();
    _instance = null;
    _defaultSettings = const InterceptlySettings();
  }

  /// Unique ID for this engine instance to isolate temporary files.
  final String engineId;

  InterceptlySettings _settings;
  late final MemoryIndex _memoryIndex;
  late final CapturePipeline _capturePipeline;
  late final PendingTracker _pendingTracker;
  late final RealtimeStore _realtimeStore;
  late final DetailLoader _detailLoader;

  NetworkSimulationProfile _networkSimulation = NetworkSimulationProfile.none;
  Future<void>? _clearFuture;
  bool _enabled = true;
  bool _isDisposed = false;
  int _entriesVersion = 0;
  final List<IndexEntry> _recentChangedEntries = [];
  Timer? _coalesceNotifyTimer;
  bool _hasPendingCoalescedNotify = false;

  InterceptlySettings get settings => _settings;

  /// Whether this engine has been disposed.
  bool get isDisposed => _isDisposed;

  int get entriesVersion => _entriesVersion;

  /// Entries that were added or updated since the last notification cycle.
  List<IndexEntry> get recentChangedEntries =>
      List.unmodifiable(_recentChangedEntries);

  bool get isEnabled => _enabled;

  int get droppedCount => _capturePipeline.droppedCount;

  NetworkSimulationProfile get networkSimulation => _networkSimulation;

  int get totalEntries => _memoryIndex.length;

  bool _realtimeExplicitlyEnabled = false;

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

  /// Returns captured entries in newest-first order.
  List<RequestSummary> get entries =>
      _memoryIndex.entries.cast<RequestSummary>();

  /// Path to the active REST temporary file on disk.
  String? get tempFilePath => _capturePipeline.tempFilePath;

  /// Current file rotation count for the REST temporary file.
  int get fileRotationCount => _capturePipeline.fileRotationCount;

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
    notifyListeners();
  }

  /// Configures settings for this engine instance.
  void configure(InterceptlySettings newSettings) =>
      _applySettings(newSettings);

  /// Initializes background workers and disk storage.
  Future<void> initialize() async {
    await _capturePipeline.initialize();
    if (_settings.persistToDisk) {
      await _realtimeStore.ensureDiskStorageInitialized(
        persistToDisk: true,
        engineId: engineId,
      );
    }
  }

  void _onCaptureReady(IndexEntry entry) {
    _entriesVersion++;
    _memoryIndex.add(entry);
    _recentChangedEntries.add(entry);
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
        _recentChangedEntries.clear();
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
        _recentChangedEntries.clear();
      }
    }
  }

  void _onPendingTimeout(IndexEntry timedOutEntry) {
    _entriesVersion++;
    _recentChangedEntries.add(timedOutEntry);
    notifyListeners();
    _recentChangedEntries.clear();
  }

  /// Enables traffic capture.
  void enable() {
    if (_isDisposed || _enabled) return;
    _enabled = true;
    notifyListeners();
  }

  /// Disables traffic capture, dropping new captures silently.
  void disable() {
    if (!_enabled) return;
    _enabled = false;
    notifyListeners();
  }

  void setNetworkSimulation(NetworkSimulationProfile profile) {
    _networkSimulation = profile;
    notifyListeners();
  }

  void clearNetworkSimulation() {
    if (_networkSimulation.isNoThrottling) return;
    _networkSimulation = NetworkSimulationProfile.none;
    notifyListeners();
  }

  /// Applies simulated upload network latency and bandwidth throttling.
  Future<void> applyNetworkSimulationBeforeRequest(
          {required int uploadBytes}) =>
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
    final isPending = _memoryIndex.byId(capture.id)?.statusCode == 0;
    if (!isPending) {
      if (!_enabled) return;
      if (_settings.shouldCapture != null &&
          !_settings.shouldCapture!(capture.url)) {
        return;
      }
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
    final entry = _pendingTracker.recordPending(
      id: id,
      method: method,
      url: url,
      timestamp: timestamp,
      requestHeaders: requestHeaders,
      requestBodyBytes: requestBodyBytes,
      requestContentType: requestContentType,
      settings: _settings,
    );
    _recentChangedEntries.add(entry);
    _scheduleCoalescedNotify();
  }

  /// Records a captured [RealtimeFrame] into the buffer.
  Future<void> recordRealtimeFrame(RealtimeFrame frame) {
    if (!_enabled || _isDisposed) return Future<void>.value();
    final predicate = _settings.shouldCapture;
    if (predicate != null) {
      final entry = _memoryIndex.byId(frame.sessionId);
      if (entry == null) return Future<void>.value();
    }
    return _realtimeStore.recordFrame(
      frame,
      persistToDisk: _settings.persistToDisk,
      offloadThreshold: _settings.realtimeBodyOffloadThreshold,
      engineId: engineId,
    );
  }

  /// Loads full payload for [frame] asynchronously from disk or memory.
  Future<dynamic> loadRealtimePayload(RealtimeFrame frame) =>
      _realtimeStore.loadPayload(frame);

  List<RealtimeFrame> getRealtimeFrames(String sessionId) =>
      _realtimeStore.getRealtimeFrames(sessionId);

  RealtimeFrameCounts getRealtimeFrameCounts(String sessionId) =>
      _realtimeStore.getFrameCounts(sessionId);

  bool canSendRealtimeMessage(String sessionId) =>
      RealtimeTrafficCollector.instance.canSend(sessionId);

  RealtimeProtocolType? getRealtimeProtocol(String sessionId) =>
      RealtimeTrafficCollector.instance.getSender(sessionId)?.protocolType;

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
    final entry = _memoryIndex.byId(id);
    if (entry != null) {
      _recentChangedEntries.add(entry);
    }
    notifyListeners();
    _recentChangedEntries.clear();
  }

  ValueListenable<RealtimeFrameCounts> getRealtimeFrameCountsNotifier(
    String sessionId,
  ) =>
      _realtimeStore.getFrameCountsNotifier(sessionId);

  /// Looks up an entry by its unique [id] in O(1) time.
  RequestSummary? byId(String id) => _memoryIndex.byId(id);

  /// Loads the full request record by request [id].
  Future<RequestRecord> loadDetailById(String id) =>
      _detailLoader.loadDetailById(id);

  /// Loads full details for [summary].
  Future<RequestRecord> loadDetail(RequestSummary summary) {
    if (summary is IndexEntry) {
      return _detailLoader.loadDetailByEntry(summary);
    }
    return loadDetailById(summary.id);
  }

  /// Searches captured network requests across URL, method, headers, error message,
  /// and (optionally) payload bodies.
  Future<List<SearchResult>> search({
    required String query,
    bool searchBody = true,
    String statusFilter = 'all',
    String? sinceId,
    int limit = 20,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final q = trimmed.toLowerCase();
    final clampedLimit = limit.clamp(1, 100);
    final normalizedStatus = statusFilter.toLowerCase();

    // 1. Snapshot all memory entries (newest-first)
    var candidates = _memoryIndex.entries.toList();

    // 2. Cursor pagination (sinceId)
    if (sinceId != null && sinceId.isNotEmpty) {
      final index = candidates.indexWhere((e) => e.id == sinceId);
      if (index > 0) {
        candidates = candidates.sublist(0, index);
      } else if (index == 0) {
        return const [];
      }
    }

    // 3. Status filter
    if (normalizedStatus != 'all') {
      candidates = candidates.where((e) {
        final code = e.statusCode;
        return switch (normalizedStatus) {
          'failed' => e.hasError || code >= 400,
          '2xx' => code >= 200 && code < 300,
          '3xx' => code >= 300 && code < 400,
          '4xx' => code >= 400 && code < 500,
          '5xx' => code >= 500 && code < 600,
          _ => true,
        };
      }).toList();
    }

    final results = <SearchResult>[];
    final fileCandidates = <(IndexEntry, int, int)>[];

    // 4. Phase 1 & Phase 2 scan
    for (final e in candidates) {
      if (results.length >= clampedLimit) break;

      // Phase 1: Structured metadata scan (RAM)
      final scopes = SearchMatcher.matchStructured(e, q);
      if (scopes.isNotEmpty) {
        results.add(SearchResult(summary: e, matchScopes: scopes));
        continue; // Short-circuit: already matched metadata, skip reading body
      }

      // If searchBody is disabled, don't check Phase 2 / Phase 3
      if (!searchBody) continue;

      // Content-type guard: skip binary payloads
      if (_isBinaryContentType(e.responseContentType) &&
          _isBinaryContentType(e.requestContentType)) {
        continue;
      }

      // Phase 2: In-memory body scan
      if (e.bodyLocation == BodyLocation.memory &&
          SearchMatcher.matchInlineBody(e, q)) {
        results.add(SearchResult(
          summary: e,
          matchScopes: const {SearchMatchScope.body},
        ));
        continue;
      }

      // Collect file candidates for Phase 3
      final isExpiredByRotation = e.fileRotationCount != null &&
          e.fileRotationCount! < _capturePipeline.fileRotationCount;

      if (!isExpiredByRotation &&
          e.bodyLocation == BodyLocation.file &&
          e.fileOffset != null &&
          e.fileLength != null) {
        fileCandidates.add((e, e.fileOffset!, e.fileLength!));
      }
    }

    // 5. Phase 3: File-backed body scan (if more results needed and file candidates exist)
    final tempFilePath = _capturePipeline.tempFilePath;
    if (searchBody &&
        results.length < clampedLimit &&
        fileCandidates.isNotEmpty &&
        tempFilePath != null) {
      RandomAccessFile? raf;
      try {
        raf = await BodyStore.openReadHandle(tempFilePath);
        for (final (e, offset, length) in fileCandidates) {
          if (results.length >= clampedLimit) break;
          final matched =
              await SearchMatcher.matchFileBody(raf, offset, length, q);
          if (matched) {
            results.add(SearchResult(
              summary: e,
              matchScopes: const {SearchMatchScope.body},
            ));
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Interceptly] engine search file read error: $e');
        }
      } finally {
        await raf?.close();
      }
    }

    return results;
  }

  static bool _isBinaryContentType(String? contentType) {
    if (contentType == null) return false;
    final ct = contentType.toLowerCase();
    return ct.startsWith('image/') ||
        ct.startsWith('video/') ||
        ct.startsWith('audio/') ||
        ct.contains('octet-stream') ||
        ct.contains('pdf') ||
        ct.contains('zip');
  }

  /// Records an entry directly into the memory index for testing.
  @visibleForTesting
  void recordEntryForTesting(IndexEntry entry) {
    _memoryIndex.add(entry);
  }

  Future<void> clear() async {
    if (_clearFuture != null) return _clearFuture!;
    final future = _performClear();
    _clearFuture = future;
    try {
      await future;
    } finally {
      if (identical(_clearFuture, future)) _clearFuture = null;
    }
  }

  Future<void> clearRest() async {
    if (_clearFuture != null) return _clearFuture!;
    final future = _performScopedClear(isRealtime: false);
    _clearFuture = future;
    try {
      await future;
    } finally {
      if (identical(_clearFuture, future)) _clearFuture = null;
    }
  }

  Future<void> clearRealtime() async {
    if (_clearFuture != null) return _clearFuture!;
    final future = _performScopedClear(isRealtime: true);
    _clearFuture = future;
    try {
      await future;
    } finally {
      if (identical(_clearFuture, future)) _clearFuture = null;
    }
  }

  /// Removes entries of one scope while keeping the other intact.
  Future<void> _performScopedClear({required bool isRealtime}) async {
    try {
      _coalesceNotifyTimer?.cancel();
      _coalesceNotifyTimer = null;
      _hasPendingCoalescedNotify = false;
      _entriesVersion++;
      _recentChangedEntries.clear();
      final ids = _memoryIndex.entries
          .where((e) => e.isRealtime == isRealtime)
          .map((e) => e.id)
          .toList();
      if (!isRealtime) {
        if (_capturePipeline.isInitialized) {
          await _capturePipeline.clear();
        } else {
          _capturePipeline.clearSync();
        }
      }
      for (final id in ids) {
        _pendingTracker.cancel(id);
      }
      _memoryIndex.removeWhere((e) => e.isRealtime == isRealtime);
      if (isRealtime) {
        _realtimeStore.clear();
      }
      if (!_isDisposed) {
        notifyListeners();
      }
      if (isRealtime) {
        await _realtimeStore.resetDiskStorage();
      }
    } finally {
      _clearFuture = null;
    }
  }

  Future<void> _performClear() async {
    try {
      _coalesceNotifyTimer?.cancel();
      _coalesceNotifyTimer = null;
      _hasPendingCoalescedNotify = false;
      _entriesVersion++;
      _recentChangedEntries.clear();
      if (_capturePipeline.isInitialized) {
        await _capturePipeline.clear();
      } else {
        _capturePipeline.clearSync();
      }
      _memoryIndex.clear();
      _pendingTracker.clear();
      _realtimeStore.clear();
      if (!_isDisposed) {
        notifyListeners();
      }
      await _realtimeStore.resetDiskStorage();
    } finally {
      _clearFuture = null;
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      throw StateError('InterceptlyEngine has already been disposed.');
    }
    _isDisposed = true;
    if (identical(_instance, this)) {
      _instance = null;
    }
    _coalesceNotifyTimer?.cancel();
    _coalesceNotifyTimer = null;
    _hasPendingCoalescedNotify = false;
    _enabled = false;
    _pendingTracker.dispose();
    _memoryIndex.clear();
    await _capturePipeline.dispose();
    await _realtimeStore.dispose();
    super.dispose();
  }
}
