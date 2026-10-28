import 'dart:async';

import 'package:flutter/foundation.dart';

import '../adapter/realtime_traffic_collector.dart';
import '../model/index_entry.dart';
import '../model/interceptly_settings.dart';
import '../model/network_simulation.dart';
import '../model/raw_capture.dart';
import '../model/realtime_frame.dart';
import '../model/realtime_protocol_type.dart';
import '../model/request_record.dart';
import '../model/request_summary.dart';
import '../model/search_result.dart';
import '../simulation/network_simulation_service.dart';
import 'capture_generation.dart';
import 'capture_pipeline.dart';
import 'detail_loader.dart';
import 'memory_index.dart';
import 'pending_tracker.dart';
import 'realtime_store.dart';
import 'search_service.dart';

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

  /// Release-guard decision shared by the engine gates and tests.
  ///
  /// Returns `false` only when [isReleaseMode] is true and the caller has
  /// not opted in via [InterceptlySettings.allowInRelease].
  static bool shouldEnableCapture({
    required bool isReleaseMode,
    required InterceptlySettings settings,
  }) =>
      !(isReleaseMode && !settings.allowInRelease);

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
  Future<void>? _clearRestFuture;
  Future<void>? _clearRealtimeFuture;
  bool _enabled = true;
  bool _isDisposed = false;
  int _entriesVersion = 0;
  final List<IndexEntry> _recentChangedEntries = [];
  final Map<String, int> _pendingGenerations = {};
  final Map<String, _ActiveRealtimeSession> _activeRealtimeSessions = {};
  Timer? _coalesceNotifyTimer;
  bool _hasPendingCoalescedNotify = false;

  /// Current generation number for HTTP capture fencing across clear operations.
  int get httpGeneration => _capturePipeline.generation;

  InterceptlySettings get settings => _settings;

  /// Whether this engine has been disposed.
  bool get isDisposed => _isDisposed;

  int get entriesVersion => _entriesVersion;

  /// Entries that were added or updated since the last notification cycle.
  List<IndexEntry> get recentChangedEntries =>
      List.unmodifiable(_recentChangedEntries);

  bool get isEnabled =>
      !_isDisposed &&
      _enabled &&
      shouldEnableCapture(
        isReleaseMode: kReleaseMode,
        settings: _settings,
      );

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

  /// Applies [newSettings] without changing the user's capture intent.
  ///
  /// Release permission is evaluated dynamically by [isEnabled], so
  /// `configure` never resumes an explicitly disabled engine. A caller that
  /// wants to resume capture must call [enable] explicitly.
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
  ///
  /// Worker creation is gated by release permission, not by the user's pause
  /// intent: a paused debug/profile engine may still be initialized
  /// explicitly, while a denied release engine must not create files or
  /// isolates. Repeating the call after opt-in retries initialization.
  Future<void> initialize() async {
    if (_isDisposed ||
        !shouldEnableCapture(
          isReleaseMode: kReleaseMode,
          settings: _settings,
        )) {
      return;
    }
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

  /// Enables traffic capture intent.
  ///
  /// This never grants release permission: [isEnabled] still composes the
  /// intent with [shouldEnableCapture]. In a denied release build the call
  /// records the intent for a later opt-in but captures nothing.
  void enable() {
    if (_isDisposed || _enabled) return;
    _enabled = true;
    notifyListeners();
  }

  /// Disables traffic capture, dropping new captures silently.
  ///
  /// The explicit pause survives [configure] until [enable] is called.
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

  /// Evaluates the user capture predicate fail-open.
  ///
  /// A throwing predicate never breaks the host request; the capture
  /// proceeds as if allowed.
  bool _predicateAllows(String url) {
    final predicate = _settings.shouldCapture;
    if (predicate == null) return true;
    try {
      return predicate(url);
    } catch (_) {
      return true;
    }
  }

  /// Enqueues [capture] for asynchronous background processing.
  void record(RawCapture capture) {
    final pendingGen = _pendingGenerations.remove(capture.id);
    final effectiveGen = readCaptureGeneration(capture) ?? pendingGen;
    if (effectiveGen != null && effectiveGen != _capturePipeline.generation) {
      return;
    }

    if (!isEnabled) return;
    if (!_predicateAllows(capture.url)) return;
    if (effectiveGen != null) {
      attachCaptureGeneration(capture, effectiveGen);
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
    if (!isEnabled) return;
    if (!_predicateAllows(url)) {
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
    if (!entry.isRealtime) {
      final maxTracked = _settings.maxEntries * 4;
      if (_pendingGenerations.length >= maxTracked &&
          _pendingGenerations.isNotEmpty) {
        _pendingGenerations.remove(_pendingGenerations.keys.first);
      }
      _pendingGenerations[id] = _capturePipeline.generation;
    }
    _recentChangedEntries.add(entry);
    _scheduleCoalescedNotify();
  }

  /// Records a captured [RealtimeFrame] into the buffer.
  Future<void> recordRealtimeFrame(RealtimeFrame frame) {
    if (!isEnabled) return Future<void>.value();
    final activeSession = _activeRealtimeSessions[frame.sessionId];
    if (activeSession != null) {
      if (!activeSession.isCaptured) return Future<void>.value();
      if (_memoryIndex.byId(frame.sessionId) == null) {
        _recordPendingEntry(
          id: activeSession.id,
          method: activeSession.method,
          url: activeSession.url,
          timestamp: activeSession.timestamp,
          requestHeaders: activeSession.headers,
        );
      }
    } else if (_settings.shouldCapture != null) {
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
  ///
  /// Defensive copy: retention outlives caller map lifetime; also bounds
  /// active sessions to avoid unbounded growth when close is never called.
  void recordRealtimeConnection({
    required String id,
    required String url,
    Map<String, String> headers = const {},
    DateTime? timestamp,
    bool isPreValidated = false,
    RealtimeProtocolType protocolType = RealtimeProtocolType.webSocket,
  }) {
    if (!isEnabled) return;
    final effectiveTimestamp = timestamp ?? DateTime.now();
    final isCaptured = isPreValidated || _predicateAllows(url);
    final active = _ActiveRealtimeSession(
      id: id,
      url: url,
      headers: Map.unmodifiable(Map<String, String>.of(headers)),
      timestamp: effectiveTimestamp,
      protocolType: protocolType,
      isCaptured: isCaptured,
    );
    if (_activeRealtimeSessions.length >= _settings.maxEntries * 2 &&
        !_activeRealtimeSessions.containsKey(id)) {
      _activeRealtimeSessions.remove(_activeRealtimeSessions.keys.first);
    }
    _activeRealtimeSessions[id] = active;
    if (!isCaptured) {
      return;
    }
    markRealtimeActive();
    _recordPendingEntry(
      id: id,
      method: active.method,
      url: url,
      timestamp: effectiveTimestamp,
      requestHeaders: active.headers,
    );
  }

  /// Records closing of an active realtime connection with close code and reason.
  void closeRealtimeConnection(
    String id, {
    int closeCode = 1000,
    String? closeReason,
  }) {
    if (_isDisposed) return;
    _activeRealtimeSessions.remove(id);
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
    int? Function()? fileRotationCountProvider,
  }) {
    return SearchService.search(
      entries: _memoryIndex.entries.toList(),
      query: query,
      filePath: _capturePipeline.tempFilePath,
      fileRotationCount: _capturePipeline.fileRotationCount,
      fileRotationCountProvider:
          fileRotationCountProvider ?? () => _capturePipeline.fileRotationCount,
      searchBody: searchBody,
      statusFilter: statusFilter,
      sinceId: sinceId,
      limit: limit,
    );
  }

  /// Records an entry directly into the memory index for testing.
  @visibleForTesting
  void recordEntryForTesting(IndexEntry entry) {
    _memoryIndex.add(entry);
  }

  /// Clears all entries, coalescing concurrent calls to an identical future.
  Future<void> clear() {
    if (_clearFuture != null) return _clearFuture!;
    final future = _performClear();
    _clearFuture = future;
    future.whenComplete(() {
      if (identical(_clearFuture, future)) _clearFuture = null;
    }).ignore();
    return future;
  }

  /// Clears REST entries only, coalescing concurrent calls to an identical future.
  Future<void> clearRest() {
    if (_clearRestFuture != null) return _clearRestFuture!;
    final future = _performScopedClear(isRealtime: false);
    _clearRestFuture = future;
    future.whenComplete(() {
      if (identical(_clearRestFuture, future)) _clearRestFuture = null;
    }).ignore();
    return future;
  }

  /// Clears realtime entries only, coalescing concurrent calls to an identical future.
  Future<void> clearRealtime() {
    if (_clearRealtimeFuture != null) return _clearRealtimeFuture!;
    final future = _performScopedClear(isRealtime: true);
    _clearRealtimeFuture = future;
    future.whenComplete(() {
      if (identical(_clearRealtimeFuture, future)) _clearRealtimeFuture = null;
    }).ignore();
    return future;
  }

  /// Removes entries of one scope while keeping the other intact.
  Future<void> _performScopedClear({required bool isRealtime}) async {
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
  }

  Future<void> _performClear() async {
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
    _pendingGenerations.clear();
    if (!_isDisposed) {
      notifyListeners();
    }
    await _realtimeStore.resetDiskStorage();
  }

  /// Disposes background workers and storage, idempotent on repeat calls.
  ///
  /// Mirrors [CapturePipeline.dispose] early-return semantics: a second call
  /// is a no-op so test teardown and [resetForTesting] never throw.
  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    if (identical(_instance, this)) {
      _instance = null;
    }
    _coalesceNotifyTimer?.cancel();
    _coalesceNotifyTimer = null;
    _hasPendingCoalescedNotify = false;
    _enabled = false;
    _pendingGenerations.clear();
    _activeRealtimeSessions.clear();
    _pendingTracker.dispose();
    _memoryIndex.clear();
    await _capturePipeline.dispose();
    await _realtimeStore.dispose();
    super.dispose();
  }
}

class _ActiveRealtimeSession {
  const _ActiveRealtimeSession({
    required this.id,
    required this.url,
    required this.headers,
    required this.timestamp,
    required this.protocolType,
    required this.isCaptured,
  });

  final String id;
  final String url;
  final Map<String, String> headers;
  final DateTime timestamp;
  final RealtimeProtocolType protocolType;
  final bool isCaptured;

  String get method => switch (protocolType) {
        RealtimeProtocolType.webSocket => 'WS',
        RealtimeProtocolType.socketIo => 'SIO',
        RealtimeProtocolType.sse => 'SSE',
      };
}
