import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/queue/bounded_event_queue.dart';
import '../model/body_location.dart';
import '../model/http_call_filter.dart';
import '../model/index_entry.dart';
import '../model/net_specter_settings.dart';
import '../model/raw_capture.dart';
import '../model/request_record.dart';
import 'body_store.dart';
import 'memory_index.dart';
import 'writer_isolate.dart';

/// Central lifecycle manager for the NetSpecter session.
///
/// Owns the [MemoryIndex] (in-RAM list view data) and the [WriterIsolate]
/// (serialised disk writer for large bodies).
///
/// All public methods are safe to call from the main isolate.
class InspectorSession extends ChangeNotifier {
  InspectorSession({NetSpecterSettings? settings})
      : settings = settings ?? const NetSpecterSettings() {
    _memoryIndex = MemoryIndex(maxEntries: this.settings.maxEntries);
    _writerIsolate = WriterIsolate(this.settings);
    _preInitQueue = BoundedEventQueue(maxSize: this.settings.maxQueuedEvents);
  }

  static InspectorSession? _instance;

  static InspectorSession get instance {
    return _instance ??= InspectorSession();
  }

  final NetSpecterSettings settings;
  late final MemoryIndex _memoryIndex;
  late final WriterIsolate _writerIsolate;
  late final BoundedEventQueue<RawCapture> _preInitQueue;
  StreamSubscription<IndexEntry>? _resultSub;

  Future<void>? _initFuture;
  bool _initialized = false;
  bool _enabled = true;
  bool _clearing = false;

  /// Captures sent to the isolate but not yet returned as [IndexEntry].
  int _inFlight = 0;
  int _droppedCount = 0;

  /// Pre-resolved temp file path (set during [initialize], main isolate only).
  String? _tempFilePath;

  HttpCallFilter _filter = const HttpCallFilter();

  HttpCallFilter get filter => _filter;
  List<IndexEntry> get entries => _memoryIndex.filtered(_filter);
  int get totalEntries => _memoryIndex.length;
  int get droppedCount => _droppedCount;
  bool get isEnabled => _enabled;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    _initFuture ??= _performInit();
    return _initFuture;
  }

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
    RawCapture? pending;
    while ((pending = _preInitQueue.removeFirstOrNull()) != null) {
      _sendCapture(pending!);
    }
  }

  void _onEntryReady(IndexEntry entry) {
    _inFlight--;
    _memoryIndex.add(entry);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Capture control
  // ---------------------------------------------------------------------------

  /// Enables capture. Capture is enabled by default.
  void enable() {
    _enabled = true;
  }

  /// Disables capture. The interceptor still runs but all [record] calls are
  /// silently dropped. Useful for hiding sensitive screens (e.g. payment flows).
  void disable() {
    _enabled = false;
  }

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

  // ---------------------------------------------------------------------------
  // Filter
  // ---------------------------------------------------------------------------

  void applyFilter(HttpCallFilter filter) {
    _filter = filter;
    notifyListeners();
  }

  void clearFilter() {
    _filter = const HttpCallFilter();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Detail loading
  // ---------------------------------------------------------------------------

  /// Load the full [RequestRecord] for [entry].
  ///
  /// - [BodyLocation.memory]: decodes inline bytes, zero I/O.
  /// - [BodyLocation.file]: reads only the specific region via
  ///   [BodyStore.readBytes] — never recreates or deletes the file.
  Future<RequestRecord> loadDetail(IndexEntry entry) async {
    String? reqPreview;
    String? resPreview;
    bool isTruncated = entry.isBodyTruncated;

    if (entry.bodyLocation == BodyLocation.memory) {
      reqPreview =
          _decodeBody(entry.inlineRequestBody, entry.requestContentType);
      resPreview =
          _decodeBody(entry.inlineResponseBody, entry.responseContentType);
    } else {
      final offset = entry.fileOffset;
      final length = entry.fileLength;
      final filePath = _tempFilePath;

      if (offset != null && length != null && filePath != null) {
        try {
          // Static read — creates a read-only handle, never modifies the file.
          final raw = await BodyStore.readBytes(filePath, offset, length);
          final decoded = raw.length > _kComputeThreshold
              ? await compute(_unpackBodies, raw)
              : _unpackBodies(raw);
          reqPreview = decoded.$1;
          resPreview = decoded.$2;
          isTruncated = isTruncated || decoded.$3;
        } catch (_) {
          reqPreview = '[body unavailable]';
          resPreview = '[body unavailable]';
        }
      }
    }

    return RequestRecord(
      id: entry.id,
      method: entry.method,
      url: entry.url,
      statusCode: entry.statusCode,
      durationMs: entry.durationMs,
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
      _filter = const HttpCallFilter();
      notifyListeners();
    } finally {
      _clearing = false;
    }
  }

  @override
  Future<void> dispose() async {
    await _resultSub?.cancel();
    await _writerIsolate.dispose();
    await _memoryIndex.dispose();
    _preInitQueue.clear();
    _initialized = false;
    _inFlight = 0;
    _initFuture = null;
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Body decode helpers
  // ---------------------------------------------------------------------------

  /// Bytes above this threshold are decoded in a background isolate via
  /// [compute] to avoid blocking the main isolate for tens of milliseconds.
  static const int _kComputeThreshold = 100 * 1024; // 100 KB

  static String? _decodeBody(Uint8List? bytes, String? contentType) {
    if (bytes == null || bytes.isEmpty) return null;
    if (_isBinaryContentType(contentType)) {
      return '[binary: ${bytes.length} bytes]';
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return '[binary: ${bytes.length} bytes]';
    }
  }

  static bool _isBinaryContentType(String? contentType) {
    if (contentType == null) return false;
    final lower = contentType.toLowerCase();
    return lower.contains('image/') ||
        lower.contains('audio/') ||
        lower.contains('video/') ||
        lower.contains('application/pdf') ||
        lower.contains('application/octet-stream') ||
        lower.contains('application/zip');
  }

  static (String?, String?, bool) _unpackBodies(Uint8List raw) {
    try {
      final json = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      final reqBase64 = json['req'] as String?;
      final resBase64 = json['res'] as String?;
      final truncated = json['truncated'] as bool? ?? false;

      final req = reqBase64 != null ? _tryUtf8(base64.decode(reqBase64)) : null;
      final res = resBase64 != null ? _tryUtf8(base64.decode(resBase64)) : null;
      return (req, res, truncated);
    } catch (_) {
      return (null, null, false);
    }
  }

  static String _tryUtf8(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return '[binary: ${bytes.length} bytes]';
    }
  }
}
