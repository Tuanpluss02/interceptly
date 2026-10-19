import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
import '../session/capture_pipeline.dart';
import '../session/detail_loader.dart';
import '../session/memory_index.dart';
import '../session/pending_tracker.dart';
import '../session/realtime_body_store.dart';
import '../session/realtime_store.dart';
import '../session/writer_isolate.dart';
import '../simulation/network_simulation_service.dart';

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
    _realtimeBodyStore = RealtimeBodyStore();
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
  late final RealtimeBodyStore _realtimeBodyStore;
  late final DetailLoader _detailLoader;
  String? _realtimeDirPath;
  Future<void>? _realtimeBodyStoreInitFuture;

  NetworkSimulationProfile _networkSimulation = NetworkSimulationProfile.none;
  Future<void>? _clearFuture;
  bool _enabled = true;
  bool _isDisposed = false;
  int _entriesVersion = 0;
  Timer? _coalesceNotifyTimer;
  bool _hasPendingCoalescedNotify = false;

  InterceptlySettings get settings => _settings;

  /// Whether this engine has been disposed.
  bool get isDisposed => _isDisposed;

  int get entriesVersion => _entriesVersion;

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
      fileName: 'interceptly_${engineId}_realtime.tmp',
    );
  }

  void _onCaptureReady(IndexEntry entry) {
    _entriesVersion++;
    _memoryIndex.add(entry);
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
    notifyListeners();
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

    try {
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
    } catch (error) {
      debugPrint(
        '[Interceptly] realtime body offload fallback to memory: $error',
      );
    }
  }

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
    notifyListeners();
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
      if (isRealtime &&
          _realtimeBodyStore.isInitialized &&
          _realtimeDirPath != null) {
        await _realtimeBodyStore.resetFile(_realtimeDirPath!);
        _realtimeBodyStoreInitFuture = null;
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
      throw StateError('InterceptlyEngine has already been disposed.');
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
    await _capturePipeline.dispose();
    await _realtimeBodyStore.dispose();
    super.dispose();
  }

  /// Forces file rotation on the engine's [RealtimeBodyStore] for testing.
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

  /// Total count of realtime frames currently retained across all connections for testing.
  @visibleForTesting
  int get totalRealtimeFramesForTesting =>
      _realtimeStore.totalFramesAcrossSessions;

  /// Flushes pending operations in [RealtimeBodyStore] for testing.
  @visibleForTesting
  Future<void> flushRealtimeBodyStoreForTesting() =>
      // ignore: invalid_use_of_visible_for_testing_member
      _realtimeBodyStore.flushForTesting();
}
