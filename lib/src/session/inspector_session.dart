import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../model/body_location.dart';
import '../model/domain_group.dart';
import '../model/index_entry.dart';
import '../model/interceptly_settings.dart';
import '../model/network_simulation.dart';
import '../model/raw_capture.dart';
import '../model/request_filter.dart';
import '../model/request_record.dart';
import '../model/request_summary.dart';
import '../session/bounded_event_queue.dart';
import '../simulation/network_simulation_service.dart';
import 'body_decode_service.dart';
import 'body_store.dart';
import 'grouping_controller.dart';
import 'inspector_preferences.dart';
import 'inspector_session_view.dart';
import 'master_search_controller.dart';
import 'memory_index.dart';
import 'writer_isolate.dart';

/// Central lifecycle manager for the Interceptly session.
///
/// Owns the [MemoryIndex] (in-RAM list view data) and the [WriterIsolate]
/// (serialised disk writer for large bodies).
///
/// All public methods are safe to call from the main isolate.
class InspectorSession extends ChangeNotifier implements InspectorSessionView {
  InspectorSession({InterceptlySettings? settings})
      : settings = settings ?? const InterceptlySettings() {
    _memoryIndex = MemoryIndex(maxEntries: this.settings.maxEntries);
    _writerIsolate = WriterIsolate(this.settings);
    _preInitQueue = BoundedEventQueue(maxSize: this.settings.maxQueuedEvents);
    _search.addListener(_onSearchChanged);
    _grouping.addListener(notifyListeners);
    _preferences.addListener(notifyListeners);
  }

  static InspectorSession? _instance;

  static InspectorSession get instance {
    return _instance ??= InspectorSession();
  }

  @override
  final InterceptlySettings settings;
  late final MemoryIndex _memoryIndex;
  late final WriterIsolate _writerIsolate;
  late final BoundedEventQueue<RawCapture> _preInitQueue;
  StreamSubscription<IndexEntry>? _resultSub;

  Future<void>? _initFuture;
  bool _initialized = false;
  bool _enabled = true;
  bool _clearing = false;
  final InspectorPreferences _preferences = InspectorPreferences();
  NetworkSimulationProfile _networkSimulation = NetworkSimulationProfile.none;
  final Map<String, Timer> _pendingTimers = {};
  static const Duration _pendingTimeout = Duration(seconds: 45);

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

  // Grouping getters
  @override
  bool get groupingEnabled => _grouping.enabled;

  @override
  Set<String> get availableDomains {
    return _memoryIndex.entries
        .map((entry) => RequestFilter.extractDomain(entry.url))
        .toSet();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    _initFuture ??= _performInit();
    return _initFuture;
  }

  void _onSearchChanged() => notifyListeners();

  Future<void> _performInit() async {
    if (_initialized) return;

    // Resolve the temp directory HERE on the main isolate — never inside
    // the background isolate where platform channels are unavailable.
    final dir = await getTemporaryDirectory();
    _tempFilePath = '${dir.path}/${BodyStore.kFileName}';

    await _writerIsolate.start(tempDirPath: dir.path);
    _resultSub = _writerIsolate.results.listen(_onEntryReady);
    _initialized = true;

    // Flush captures buffered before the isolate was ready.
    // Runs synchronously (no awaits) so no new record() call can interleave.
    _droppedCount += _preInitQueue.droppedCount;
    _preferences.setUrlDecodeEnabled(settings.urlDecodeEnabled);
    RawCapture? pending;
    while ((pending = _preInitQueue.removeFirstOrNull()) != null) {
      _sendCapture(pending!);
    }
  }

  void _onEntryReady(IndexEntry entry) {
    _inFlight--;
    _cancelPendingTimeout(entry.id);
    _memoryIndex.add(entry);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Capture control
  // ---------------------------------------------------------------------------

  /// Enables capture. Capture is enabled by default.
  @override
  void enable() {
    _enabled = true;
  }

  /// Disables capture. The interceptor still runs but all [record] calls are
  /// silently dropped. Useful for hiding sensitive screens (e.g. payment flows).
  @override
  void disable() {
    _enabled = false;
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

  // ---------------------------------------------------------------------------
  // Grouping
  // ---------------------------------------------------------------------------

  @override
  void toggleGrouping(bool enabled) => _grouping.setEnabled(enabled);

  @override
  void toggleDomainExpanded(String domain) =>
      _grouping.toggleDomainExpanded(domain);

  @override
  List<DomainGroup> getGroupedRecords() {
    final grouped = <String, List<RequestSummary>>{};
    for (final entry in entries) {
      final domain = RequestFilter.extractDomain(entry.url);
      grouped.putIfAbsent(domain, () => []).add(entry);
    }
    return grouped.entries
        .map(
          (e) => DomainGroup(
            domain: e.key,
            requests: e.value,
            isExpanded: _grouping.isExpanded(e.key),
          ),
        )
        .toList();
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
    if (!_initialized) {
      // Buffer until the isolate is ready; bounded by maxQueuedEvents.
      _preInitQueue.add(capture);
      initialize();
      return;
    }
    _sendCapture(capture);
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

    final inlineRequestBody = BodyDecodeService.truncate(
      requestBodyBytes,
      settings.maxBodyBytes,
      settings.previewTruncationBytes,
    );
    final isTruncated = requestBodyBytes != null &&
        requestBodyBytes.length > settings.maxBodyBytes;

    _memoryIndex.add(
      IndexEntry(
        id: id,
        method: method,
        url: url,
        statusCode: 0,
        durationMs: 0,
        requestSizeBytes: requestBodyBytes?.length ?? 0,
        responseSizeBytes: 0,
        timestamp: timestamp,
        hasError: false,
        bodyLocation: BodyLocation.memory,
        inlineRequestBody: inlineRequestBody,
        inlineResponseBody: null,
        requestHeaders: requestHeaders,
        responseHeaders: const {},
        requestContentType: requestContentType,
        responseContentType: null,
        errorType: null,
        errorMessage: null,
        isBodyTruncated: isTruncated,
        fileOffset: null,
        fileLength: null,
      ),
    );
    _schedulePendingTimeout(id);
    notifyListeners();
  }

  void _schedulePendingTimeout(String id) {
    _cancelPendingTimeout(id);
    _pendingTimers[id] = Timer(_pendingTimeout, () {
      _pendingTimers.remove(id);

      IndexEntry? current;
      for (final entry in _memoryIndex.entries) {
        if (entry.id == id) {
          current = entry;
          break;
        }
      }

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
          isBodyTruncated: current.isBodyTruncated,
          fileOffset: current.fileOffset,
          fileLength: current.fileLength,
        ),
      );
      notifyListeners();
    });
  }

  void _cancelPendingTimeout(String id) {
    _pendingTimers.remove(id)?.cancel();
  }

  // ---------------------------------------------------------------------------
  // Filter
  // ---------------------------------------------------------------------------

  @override
  void applyFilter(RequestFilter filter) {
    if (_filter == filter) return;
    _filter = filter;
    notifyListeners();
  }

  @override
  void clearFilter() {
    _filter = RequestFilter();
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

  // ---------------------------------------------------------------------------
  // Detail loading
  // ---------------------------------------------------------------------------

  /// Load the full [RequestRecord] for [summary].
  ///
  /// - [BodyLocation.memory]: decodes inline bytes, zero I/O.
  /// - [BodyLocation.file]: reads only the specific region via
  ///   [BodyStore.readBytes] — never recreates or deletes the file.
  @override
  Future<RequestRecord> loadDetail(RequestSummary summary) async {
    // IndexEntry extends RequestSummary — all session entries are IndexEntry.
    final entry = summary as IndexEntry;

    String? reqPreview;
    String? resPreview;
    Uint8List? reqBytes;
    Uint8List? resBytes;
    bool isTruncated = entry.isBodyTruncated;

    if (entry.bodyLocation == BodyLocation.memory) {
      reqBytes = entry.inlineRequestBody;
      resBytes = entry.inlineResponseBody;
      reqPreview = BodyDecodeService.decode(reqBytes, entry.requestContentType);
      resPreview = BodyDecodeService.decode(
        resBytes,
        entry.responseContentType,
      );
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
          reqPreview = BodyDecodeService.decode(
            reqBytes,
            entry.requestContentType,
          );
          resPreview = BodyDecodeService.decode(
            resBytes,
            entry.responseContentType,
          );
          isTruncated = isTruncated || decoded.$3;
        } catch (_) {
          reqPreview = BodyDecodeService.unavailablePlaceholder;
          resPreview = BodyDecodeService.unavailablePlaceholder;
        }
      }
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
      isBodyTruncated: isTruncated,
      errorType: entry.errorType,
      errorMessage: entry.errorMessage,
    );
  }

  // ---------------------------------------------------------------------------
  // Clear / Dispose
  // ---------------------------------------------------------------------------

  @override
  Future<void> clear() async {
    if (_clearing) return;
    _clearing = true;
    try {
      if (_initialized) {
        // Wait for the isolate to finish all pending writes AND reset the file
        // before clearing the in-memory index, so offsets never go stale.
        await _writerIsolate.clear();
      } else {
        _preInitQueue.clear();
      }
      _droppedCount = 0;
      _memoryIndex.clear();
      _filter = RequestFilter();
      _search.reset();
      for (final timer in _pendingTimers.values) {
        timer.cancel();
      }
      _pendingTimers.clear();
      notifyListeners();
    } finally {
      _clearing = false;
    }
  }

  @override
  Future<void> dispose() async {
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _grouping.removeListener(notifyListeners);
    _grouping.dispose();
    _preferences.removeListener(notifyListeners);
    _preferences.dispose();
    await _resultSub?.cancel();
    await _writerIsolate.dispose();
    _memoryIndex.clear();
    _preInitQueue.clear();
    for (final timer in _pendingTimers.values) {
      timer.cancel();
    }
    _pendingTimers.clear();
    _initialized = false;
    _inFlight = 0;
    _initFuture = null;
    super.dispose();
  }
}
