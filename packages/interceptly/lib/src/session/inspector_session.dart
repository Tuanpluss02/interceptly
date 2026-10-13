import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../model/body_location.dart';
import '../model/body_truncation.dart';
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
import '../session/bounded_event_queue.dart';
import '../simulation/network_simulation_service.dart';
import 'body_decode_service.dart';
import 'body_store.dart';
import 'grouping_controller.dart';
import 'inspector_preferences.dart';
import 'inspector_session_view.dart';
import 'master_search_controller.dart';
import 'memory_index.dart';
import 'ring_buffer.dart';
import 'writer_isolate.dart';
import '../capture/capture_guard.dart';

/// Central lifecycle manager for the Interceptly session.
///
/// Owns the [MemoryIndex] (in-RAM list view data) and the [WriterIsolate]
/// (serialised disk writer for large bodies).
///
/// All public methods are safe to call from the main isolate.
class InspectorSession extends ChangeNotifier implements InspectorSessionView {
  InspectorSession({InterceptlySettings? settings})
      : _settings = settings ?? _defaultSettings,
        sessionId = _generateSessionId() {
    _normalizedRedactedHeaders = _settings.normalizedRedactedHeaders;
    _memoryIndex = MemoryIndex(maxEntries: _settings.maxEntries);
    _writerIsolate = WriterIsolate(_settings);
    _preInitQueue = BoundedEventQueue(maxSize: _settings.maxQueuedEvents);
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

  /// Global configure helper for the shared singleton before or after first access.
  static void configure(InterceptlySettings settings) {
    _defaultSettings = settings;
    _instance?._applySettings(settings);
  }

  static InspectorSession? _instance;

  static InspectorSession get instance {
    return _instance ??= InspectorSession(settings: _defaultSettings);
  }

  /// Unique ID for this session instance to isolate temporary files.
  final String sessionId;

  InterceptlySettings _settings;
  late Set<String> _normalizedRedactedHeaders;

  @override
  InterceptlySettings get settings => _settings;

  void _applySettings(InterceptlySettings newSettings) {
    if (newSettings.maxFramesPerSession != _settings.maxFramesPerSession) {
      for (final buffer in _realtimeFramesBySession.values) {
        buffer.updateCapacity(newSettings.maxFramesPerSession);
      }
    }
    _settings = newSettings;
    _normalizedRedactedHeaders = newSettings.normalizedRedactedHeaders;
    _writerIsolate.updateSettings(newSettings);
    _memoryIndex.updateMaxEntries(newSettings.maxEntries);
    _preInitQueue.updateMaxSize(newSettings.maxQueuedEvents);
    _preferences.setUrlDecodeEnabled(newSettings.urlDecodeEnabled);
    notifyListeners();
  }

  /// Configures settings for this specific session instance.
  void configureSession(InterceptlySettings newSettings) =>
      _applySettings(newSettings);
  late final MemoryIndex _memoryIndex;
  late final WriterIsolate _writerIsolate;
  late final BoundedEventQueue<RawCapture> _preInitQueue;
  StreamSubscription<IndexEntry>? _resultSub;

  final Map<String, RingBuffer<RealtimeFrame>> _realtimeFramesBySession = {};
  Timer? _realtimeThrottleTimer;
  bool _hasPendingRealtimeFrameNotification = false;

  Future<void>? _initFuture;
  bool _initialized = false;
  bool _enabled = true;
  Future<void>? _clearFuture;
  final InspectorPreferences _preferences = InspectorPreferences();
  NetworkSimulationProfile _networkSimulation = NetworkSimulationProfile.none;
  final Map<String, Timer> _pendingTimers = {};

  /// Captures sent to the isolate but not yet returned as [IndexEntry].
  int _inFlight = 0;
  int _droppedCount = 0;

  /// Pre-resolved temp file path (set during [initialize], main isolate only).
  String? _tempFilePath;

  RequestFilter _filter = RequestFilter();
  final MasterSearchController _search = MasterSearchController();
  final GroupingController _grouping = GroupingController();

  @override
  RequestFilter get filter => _filter;

  @override
  List<RequestSummary> get entries {
    if (_search.isActive) {
      return (_search.results ?? const <IndexEntry>[]).cast<RequestSummary>();
    }
    return _memoryIndex.filtered(_filter).cast<RequestSummary>();
  }

  int get totalEntries => _memoryIndex.length;

  @override
  int get droppedCount => _droppedCount;

  @override
  bool get isEnabled => _enabled;

  @override
  InspectorPreferences get preferences => _preferences;

  @override
  NetworkSimulationProfile get networkSimulation => _networkSimulation;

  @override
  String? get masterQuery => _search.query;

  @override
  bool get isMasterSearchActive => _search.isActive;

  @override
  bool get isScanningBodies => _search.isScanningBodies;

  @override
  bool get isScanningFiles => _search.isScanningFiles;

  @override
  Set<SearchMatchScope> getSearchScopes(String id) => _search.getScopes(id);

  @override
  bool get groupingEnabled => _grouping.enabled;

  Set<String>? _cachedAvailableDomains;

  @override
  Set<String> get availableDomains {
    return _cachedAvailableDomains ??= _memoryIndex.entries
        .map((entry) => RequestFilter.extractDomain(entry.url))
        .toSet();
  }

  void _invalidateAvailableDomainsCache() {
    _cachedAvailableDomains = null;
  }

  Future<void> initialize() async {
    _initFuture ??= _performInit();
    return _initFuture;
  }

  void _onSearchChanged() => notifyListeners();

  void _onGroupingChanged() {
    _invalidateGroupedCache();
    notifyListeners();
  }

  Future<void> _performInit() async {
    if (_initialized) return;

    try {
      final dir = await getTemporaryDirectory();
      final fileName = 'interceptly_${sessionId}_session.tmp';
      _tempFilePath = '${dir.path}/$fileName';

      await BodyStore.purgeOrphanedTempFiles(
        dir.path,
        currentFileName: fileName,
      );

      await _writerIsolate.start(tempDirPath: dir.path, fileName: fileName);
      _resultSub = _writerIsolate.results.listen(_onEntryReady);
      _initialized = true;

      _droppedCount += _preInitQueue.droppedCount;
      _preferences.setUrlDecodeEnabled(settings.urlDecodeEnabled);
      while (true) {
        final pending = _preInitQueue.removeFirstOrNull();
        if (pending == null) break;
        _sendCapture(pending);
      }
    } catch (_) {
      _initFuture = null;
      rethrow;
    }
  }

  void _onEntryReady(IndexEntry entry) {
    _inFlight--;
    _cancelPendingTimeout(entry.id);
    _memoryIndex.add(entry);
    _invalidateGroupedCache();
    notifyListeners();
  }

  /// Enables capture. Capture is enabled by default.
  @override
  void enable() {
    if (_enabled) return;
    _enabled = true;
    notifyListeners();
  }

  /// Disables capture. The interceptor still runs but all [record] calls are
  /// silently dropped. Useful for hiding sensitive screens (e.g. payment flows).
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

  List<DomainGroup>? _cachedGroupedRecords;
  int _cacheVersion = 0;
  int _lastComputedCacheVersion = -1;

  void _invalidateGroupedCache() {
    _cachedGroupedRecords = null;
    _cacheVersion++;
    _invalidateAvailableDomainsCache();
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

  Future<void> applyNetworkSimulationBeforeRequest({
    required int uploadBytes,
  }) =>
      NetworkSimulationService.applyBeforeRequest(
        _networkSimulation,
        uploadBytes: uploadBytes,
      );

  Future<void> applyNetworkSimulationAfterResponse({
    required int downloadBytes,
  }) =>
      NetworkSimulationService.applyAfterResponse(
        _networkSimulation,
        downloadBytes: downloadBytes,
      );

  Duration throughputDelayForChunk(int chunkBytes) =>
      NetworkSimulationService.throughputDelayForChunk(
        _networkSimulation,
        chunkBytes,
      );

  /// Fire-and-forget: enqueue a [RawCapture] for background processing.
  /// Returns immediately — never blocks the interceptor.
  /// No-op when [isEnabled] is false or the queue is full.
  void record(RawCapture capture) {
    if (!_enabled) return;
    if (settings.shouldCapture != null &&
        !settings.shouldCapture!(capture.url)) {
      return;
    }

    final sanitizedCapture = RawCapture(
      id: capture.id,
      method: capture.method,
      url: capture.url,
      requestHeaders:
          redactHeaders(capture.requestHeaders, _normalizedRedactedHeaders),
      responseHeaders:
          redactHeaders(capture.responseHeaders, _normalizedRedactedHeaders),
      statusCode: capture.statusCode,
      durationMs: capture.durationMs,
      timestamp: capture.timestamp,
      requestBodyBytes: capture.requestBodyBytes,
      responseBodyBytes: capture.responseBodyBytes,
      requestContentType: capture.requestContentType,
      responseContentType: capture.responseContentType,
      errorType: capture.errorType,
      errorMessage: capture.errorMessage,
    );

    if (!_initialized) {
      _preInitQueue.add(sanitizedCapture);
      initialize().catchError((Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint(
              '[Interceptly] background init failed: $error\n$stackTrace');
        }
      });
      return;
    }
    _sendCapture(sanitizedCapture);
  }

  void _sendCapture(RawCapture capture) {
    if (_inFlight >= settings.maxQueuedEvents) {
      _droppedCount++;
      return;
    }
    _inFlight++;
    _writerIsolate.send(capture);
  }

  /// Inserts an immediate pending request entry so UI can render it before
  /// the response arrives.
  ///
  /// The final capture should use the same [id] so it replaces this pending
  /// row via [MemoryIndex.add] upsert.
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
    if (settings.shouldCapture != null && !settings.shouldCapture!(url)) {
      return;
    }

    final sanitizedHeaders =
        redactHeaders(requestHeaders, _normalizedRedactedHeaders);
    final inlineRequestBody = BodyDecodeService.truncate(
      requestBodyBytes,
      settings.maxBodyBytes,
      settings.previewTruncationBytes,
    );
    final requestSize = requestBodyBytes?.length ?? 0;
    final requestTruncation = _pendingRequestTruncation(
      originalBytes: requestSize,
      inlineBytes: inlineRequestBody?.length ?? 0,
    );

    _memoryIndex.add(
      IndexEntry(
        id: id,
        method: method,
        url: url,
        statusCode: 0,
        durationMs: 0,
        requestSizeBytes: requestSize,
        responseSizeBytes: 0,
        timestamp: timestamp,
        hasError: false,
        bodyLocation: BodyLocation.memory,
        inlineRequestBody: inlineRequestBody,
        inlineResponseBody: null,
        requestHeaders: sanitizedHeaders,
        responseHeaders: const {},
        requestContentType: requestContentType,
        responseContentType: null,
        errorType: null,
        errorMessage: null,
        requestTruncation: requestTruncation,
        responseTruncation: const BodyTruncation.complete(0),
        fileOffset: null,
        fileLength: null,
      ),
    );
    _schedulePendingTimeout(id);
    _invalidateGroupedCache();
    notifyListeners();
  }

  /// Records a captured [RealtimeFrame] into the session buffer and schedules
  /// a throttled notification (~100ms interval) to avoid UI message storm thrashing.
  void recordRealtimeFrame(RealtimeFrame frame) {
    if (!_enabled) return;

    final buffer = _realtimeFramesBySession.putIfAbsent(
      frame.sessionId,
      () => RingBuffer<RealtimeFrame>(capacity: settings.maxFramesPerSession),
    );
    buffer.add(frame);

    _scheduleRealtimeNotification();
  }

  void _scheduleRealtimeNotification() {
    _hasPendingRealtimeFrameNotification = true;
    _realtimeThrottleTimer ??= Timer(const Duration(milliseconds: 100), () {
      _realtimeThrottleTimer = null;
      if (_hasPendingRealtimeFrameNotification) {
        _hasPendingRealtimeFrameNotification = false;
        notifyListeners();
      }
    });
  }

  @override
  List<RealtimeFrame> getRealtimeFrames(String sessionId) {
    final buffer = _realtimeFramesBySession[sessionId];
    if (buffer == null || buffer.isEmpty) {
      return const <RealtimeFrame>[];
    }
    return buffer.toList();
  }

  @override
  List<RealtimeFrame> getFrames(String sessionId) =>
      getRealtimeFrames(sessionId);

  /// Records opening of a realtime connection (e.g. WebSocket handshake).
  void recordRealtimeConnection({
    required String id,
    required String url,
    Map<String, String> headers = const {},
    DateTime? timestamp,
  }) {
    if (!_enabled) return;
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
    _cancelPendingTimeout(id);
    final current = _memoryIndex.byId(id);
    if (current != null) {
      _memoryIndex.add(
        IndexEntry(
          id: current.id,
          method: current.method,
          url: current.url,
          statusCode: closeCode,
          durationMs:
              DateTime.now().difference(current.timestamp).inMilliseconds,
          requestSizeBytes: current.requestSizeBytes,
          responseSizeBytes: current.responseSizeBytes,
          timestamp: current.timestamp,
          hasError: closeCode > 1000 && closeCode != 1005,
          bodyLocation: current.bodyLocation,
          inlineRequestBody: current.inlineRequestBody,
          inlineResponseBody: current.inlineResponseBody,
          requestHeaders: current.requestHeaders,
          responseHeaders: current.responseHeaders,
          requestContentType: current.requestContentType,
          responseContentType: current.responseContentType,
          errorType: current.errorType,
          errorMessage: closeReason ?? current.errorMessage,
          requestTruncation: current.requestTruncation,
          responseTruncation: current.responseTruncation,
          fileOffset: current.fileOffset,
          fileLength: current.fileLength,
        ),
      );
      _invalidateGroupedCache();
      notifyListeners();
    }
  }

  /// Describes a pending row's request body.
  ///
  /// A pending row is trimmed to [InterceptlySettings.previewTruncationBytes]
  /// only when the body already exceeded `maxBodyBytes`, so shrinking is a
  /// preview-stage cut; storage itself is still intact and the real capture
  /// will upsert over this row with the full body.
  static BodyTruncation _pendingRequestTruncation({
    required int originalBytes,
    required int inlineBytes,
  }) {
    if (inlineBytes >= originalBytes) {
      return BodyTruncation.complete(originalBytes);
    }
    return BodyTruncation(
      originalBytes: originalBytes,
      retainedBytes: inlineBytes,
      stage: TruncationStage.preview,
    );
  }

  void _schedulePendingTimeout(String id) {
    _cancelPendingTimeout(id);
    _pendingTimers[id] = Timer(settings.pendingTimeout, () {
      _pendingTimers.remove(id);

      final current = _memoryIndex.byId(id);
      if (current == null) return;
      if (current.statusCode != 0 || current.hasError) return;

      _memoryIndex.add(
        IndexEntry(
          id: current.id,
          method: current.method,
          url: current.url,
          statusCode: 0,
          durationMs: current.durationMs,
          requestSizeBytes: current.requestSizeBytes,
          responseSizeBytes: current.responseSizeBytes,
          timestamp: current.timestamp,
          hasError: true,
          bodyLocation: current.bodyLocation,
          inlineRequestBody: current.inlineRequestBody,
          inlineResponseBody: current.inlineResponseBody,
          requestHeaders: current.requestHeaders,
          responseHeaders: current.responseHeaders,
          requestContentType: current.requestContentType,
          responseContentType: current.responseContentType,
          errorType: 'TimeoutException',
          errorMessage:
              'Request timed out while waiting for response or terminal error.',
          requestTruncation: current.requestTruncation,
          responseTruncation: current.responseTruncation,
          fileOffset: current.fileOffset,
          fileLength: current.fileLength,
        ),
      );
      _invalidateGroupedCache();
      notifyListeners();
    });
  }

  void _cancelPendingTimeout(String id) {
    _pendingTimers.remove(id)?.cancel();
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

  /// Cancels any in-progress master search and restores normal filtered mode.
  @override
  void cancelMasterSearch() => _search.cancel();

  /// Starts a progressive master search over all captures.
  @override
  Future<void> startMasterSearch(String query) => _search.start(
        query: query,
        allEntries: _memoryIndex.entries,
        filePath: _tempFilePath,
      );

  /// Load the full [RequestRecord] for [summary].
  ///
  /// - [BodyLocation.memory]: decodes inline bytes, zero I/O.
  /// - [BodyLocation.file]: reads only the specific region via
  ///   [BodyStore.readBytes] — never recreates or deletes the file.
  @override
  Future<RequestRecord> loadDetail(RequestSummary summary) async {
    if (summary is! IndexEntry) {
      throw ArgumentError.value(
        summary,
        'summary',
        'Expected an IndexEntry instance created by Interceptly',
      );
    }
    final entry = summary;

    String? reqPreview;
    String? resPreview;
    Uint8List? reqBytes;
    Uint8List? resBytes;
    var reqStorage = entry.requestTruncation;
    var resStorage = entry.responseTruncation;

    if (entry.bodyLocation == BodyLocation.memory) {
      reqBytes = entry.inlineRequestBody;
      resBytes = entry.inlineResponseBody;
    } else {
      final offset = entry.fileOffset;
      final length = entry.fileLength;
      final filePath = _tempFilePath;

      if (offset != null && length != null && filePath != null) {
        try {
          final raw = await BodyStore.readBytes(filePath, offset, length);
          final decoded = raw.length > BodyDecodeService.computeThreshold
              ? await compute(BodyDecodeService.unpackToBytes, raw)
              : BodyDecodeService.unpackToBytes(raw);
          reqBytes = decoded.$1;
          resBytes = decoded.$2;
          if (decoded.$3) {
            reqStorage = _markStorageCut(reqStorage, reqBytes?.length ?? 0);
            resStorage = _markStorageCut(resStorage, resBytes?.length ?? 0);
          }
        } catch (_) {
          reqPreview = BodyDecodeService.unavailablePlaceholder;
          resPreview = BodyDecodeService.unavailablePlaceholder;
        }
      }
    }

    final maxUi = _settings.maxUiPreviewBytes;

    if (reqPreview == null && reqBytes != null) {
      final reqSlice = _limitForPreview(reqBytes, maxUi);
      reqStorage =
          _applyPreviewStage(reqStorage, reqBytes.length, reqSlice.length);
      reqPreview = await BodyDecodeService.decodeAsync(
        reqSlice,
        entry.requestContentType,
      );
    }

    if (resPreview == null && resBytes != null) {
      final resSlice = _limitForPreview(resBytes, maxUi);
      resStorage =
          _applyPreviewStage(resStorage, resBytes.length, resSlice.length);
      resPreview = await BodyDecodeService.decodeAsync(
        resSlice,
        entry.responseContentType,
      );
    }

    return RequestRecord(
      id: entry.id,
      method: entry.method,
      url: entry.url,
      statusCode: entry.statusCode,
      durationMs: entry.durationMs,
      requestSizeBytes: entry.requestSizeBytes,
      responseSizeBytes: entry.responseSizeBytes,
      timestamp: entry.timestamp,
      requestHeaders: entry.requestHeaders,
      responseHeaders: entry.responseHeaders,
      requestContentType: entry.requestContentType,
      responseContentType: entry.responseContentType,
      requestBodyPreview: reqPreview,
      responseBodyPreview: resPreview,
      requestBodyBytes: reqBytes,
      responseBodyBytes: resBytes,
      requestTruncation: reqStorage,
      responseTruncation: resStorage,
      errorType: entry.errorType,
      errorMessage: entry.errorMessage,
    );
  }

  Uint8List _limitForPreview(Uint8List bytes, int maxUi) =>
      maxUi > 0 && bytes.length > maxUi ? bytes.sublist(0, maxUi) : bytes;

  /// Marks [truncation] as storage-cut, preserving the original size the
  /// network reported even when only the recovered slice is known here.
  static BodyTruncation _markStorageCut(BodyTruncation truncation, int kept) {
    return BodyTruncation(
      originalBytes: truncation.originalBytes,
      retainedBytes: kept,
      stage: TruncationStage.storage,
    );
  }

  /// Combines the storage verdict with what preview trimming just did.
  ///
  /// A body can lose bytes at both stages, so the two verdicts merge instead
  /// of overwriting: preview loss on top of an existing storage cut yields
  /// [TruncationStage.storageAndPreview].
  static BodyTruncation _applyPreviewStage(
    BodyTruncation truncation,
    int availableBytes,
    int previewBytes,
  ) {
    final previewCut = previewBytes < availableBytes;
    final storageCut = truncation.stage == TruncationStage.storage ||
        truncation.stage == TruncationStage.storageAndPreview;
    if (!previewCut) {
      return truncation;
    }
    return BodyTruncation(
      originalBytes: truncation.originalBytes,
      retainedBytes: previewBytes,
      stage: storageCut
          ? TruncationStage.storageAndPreview
          : TruncationStage.preview,
    );
  }

  @override
  Future<void> clear() async {
    if (_clearFuture != null) return _clearFuture!;
    return _clearFuture = _performClear();
  }

  Future<void> _performClear() async {
    try {
      if (_initialized) {
        await _writerIsolate.clear();
      } else {
        _preInitQueue.clear();
      }
      _droppedCount = 0;
      _memoryIndex.clear();
      _invalidateGroupedCache();
      _filter = RequestFilter();
      _search.reset();
      for (final timer in _pendingTimers.values) {
        timer.cancel();
      }
      _pendingTimers.clear();
      _realtimeThrottleTimer?.cancel();
      _realtimeThrottleTimer = null;
      _hasPendingRealtimeFrameNotification = false;
      _realtimeFramesBySession.clear();
      notifyListeners();
    } finally {
      _clearFuture = null;
    }
  }

  @override
  Future<void> dispose() async {
    _realtimeThrottleTimer?.cancel();
    _realtimeThrottleTimer = null;
    _hasPendingRealtimeFrameNotification = false;
    _realtimeFramesBySession.clear();
    for (final timer in _pendingTimers.values) {
      timer.cancel();
    }
    _pendingTimers.clear();
    _memoryIndex.clear();
    _preInitQueue.clear();
    _search.cancel();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _grouping.removeListener(_onGroupingChanged);
    _grouping.dispose();
    _preferences.removeListener(notifyListeners);
    _preferences.dispose();
    await _resultSub?.cancel();
    await _writerIsolate.dispose();
    _initialized = false;
    _inFlight = 0;
    _initFuture = null;
    if (identical(_instance, this)) {
      _instance = null;
    }
    super.dispose();
  }
}
