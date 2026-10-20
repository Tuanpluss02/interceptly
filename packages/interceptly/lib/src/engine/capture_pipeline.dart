import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../model/index_entry.dart';
import '../model/interceptly_settings.dart';
import '../model/raw_capture.dart';
import 'body_store.dart';
import 'bounded_event_queue.dart';
import 'writer_isolate.dart';

/// Pipeline managing pre-initialization queueing, asynchronous isolate writing,
/// and generation-fenced entry ingestion.
@internal
class CapturePipeline {
  /// Creates a capture pipeline configured for [sessionId] and [settings].
  CapturePipeline({
    required InterceptlySettings settings,
    required String sessionId,
    required void Function(IndexEntry entry) onEntryReady,
    void Function(String id)? onEntryReceived,
  })  : _settings = settings,
        _sessionId = sessionId,
        _onEntryReady = onEntryReady,
        _onEntryReceived = onEntryReceived,
        _writerIsolate = WriterIsolate(settings),
        _preInitQueue = BoundedEventQueue(maxSize: settings.maxQueuedEvents);

  final String _sessionId;
  final void Function(IndexEntry entry) _onEntryReady;
  final void Function(String id)? _onEntryReceived;

  InterceptlySettings _settings;

  final WriterIsolate _writerIsolate;
  final BoundedEventQueue<RawCapture> _preInitQueue;
  StreamSubscription<IndexEntry>? _resultSub;
  StreamSubscription<WriterIsolateEvent>? _eventSub;

  Future<void>? _initFuture;
  bool _initialized = false;
  int _inFlight = 0;
  int _inFlightBytes = 0;
  int _droppedCount = 0;
  int _generation = 0;
  int _fileRotationCount = 0;
  int _respawnCount = 0;
  final Map<String, int> _sentGenerations = {};
  final Map<String, int> _sentBytes = {};
  String? _tempFilePath;
  String? _activeDirPath;
  String? _activeFileName;

  static const int maxInFlightBytes = 32 * 1024 * 1024;
  static const int maxRespawns = 3;

  bool _isDisposed = false;
  bool _initFailed = false;
  bool _fallbackMode = false;
  bool _isRespawning = false;

  /// Whether the pipeline has finished asynchronous isolate initialization.
  bool get isInitialized => _initialized;

  /// Whether the pipeline has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether the pipeline initialization failed.
  bool get initFailed => _initFailed;

  /// Whether the pipeline is operating in degraded in-memory mode.
  bool get isDegraded => _initFailed || _fallbackMode;

  /// Pre-resolved temporary file path used for body offloading on disk.
  String? get tempFilePath => _tempFilePath;

  /// Number of captures dropped due to queue saturation or isolate failure.
  int get droppedCount =>
      _droppedCount +
      (_initialized || isDegraded ? 0 : _preInitQueue.droppedCount);

  /// Number of captures currently dispatched to the writer isolate.
  int get inFlight => _inFlight;

  /// Total payload bytes currently in-flight across isolate boundaries.
  int get inFlightBytes => _inFlightBytes;

  /// Underlying writer isolate.
  WriterIsolate get writerIsolate => _writerIsolate;

  /// Current generation number for fence verification.
  int get generation => _generation;

  /// Latest file rotation count observed from the writer isolate.
  int get fileRotationCount => _fileRotationCount;

  /// Updates settings propagated from session reconfiguration.
  void updateSettings(InterceptlySettings newSettings) {
    _settings = newSettings;
    _writerIsolate.updateSettings(newSettings);
    _preInitQueue.updateMaxSize(newSettings.maxQueuedEvents);
  }

  /// Initializes disk storage and boots the background writer isolate.
  Future<void> initialize() async {
    if (_isDisposed) return;
    _initFuture ??= _performInit();
    return _initFuture;
  }

  Future<void> _performInit() async {
    if (_initialized || _isDisposed) return;

    try {
      final String dirPath;
      final fileName = 'interceptly_${_sessionId}_session.tmp';
      if (_settings.persistToDisk) {
        final dir = await getTemporaryDirectory();
        if (_isDisposed) return;
        dirPath = dir.path;
        _tempFilePath = '$dirPath/$fileName';

        await BodyStore.purgeOrphanedTempFiles(
          dirPath,
          currentFileName: fileName,
          maxAge: const Duration(hours: 24),
        );
        if (_isDisposed) return;
      } else {
        dirPath = Directory.systemTemp.path;
      }

      await _writerIsolate.start(tempDirPath: dirPath, fileName: fileName);
      if (_isDisposed) {
        await _writerIsolate.dispose();
        return;
      }

      _activeDirPath = dirPath;
      _activeFileName = fileName;
      _resultSub = _writerIsolate.results.listen(_handleEntryReady);
      _eventSub = _writerIsolate.events.listen(_handleIsolateEvent);
      _initialized = true;

      _droppedCount += _preInitQueue.droppedCount;
      while (true) {
        final pending = _preInitQueue.removeFirstOrNull();
        if (pending == null) break;
        _sendCapture(pending);
      }
    } catch (error, stackTrace) {
      if (_isDisposed) return;
      _initFailed = true;
      _drainPreInitQueueToFallback();
      if (kDebugMode) {
        debugPrint(
          '[Interceptly] background init failed: $error\n$stackTrace',
        );
      }
    }
  }

  void _drainPreInitQueueToFallback() {
    if (!_initialized) {
      _droppedCount += _preInitQueue.droppedCount;
    }
    while (true) {
      final pending = _preInitQueue.removeFirstOrNull();
      if (pending == null) break;
      _processInMemory(pending);
    }
  }

  void _processInMemory(RawCapture capture) {
    _onEntryReceived?.call(capture.id);
    final entry = WriterIsolate.processInMemory(
      capture,
      maxBodyBytes: _settings.maxBodyBytes,
    );
    _onEntryReady(entry);
  }

  void _enterFallbackMode() {
    _fallbackMode = true;
    _drainPreInitQueueToFallback();
  }

  void _handleIsolateEvent(WriterIsolateEvent event) {
    if (_isDisposed || _isRespawning || _fallbackMode) return;

    _inFlight = 0;
    _inFlightBytes = 0;
    _sentBytes.clear();
    _sentGenerations.clear();

    if (_respawnCount < maxRespawns) {
      _respawnCount++;
      _respawnIsolate();
    } else {
      _enterFallbackMode();
    }
  }

  Future<void> _respawnIsolate() async {
    if (_isDisposed || _fallbackMode || _isRespawning) return;
    _isRespawning = true;
    try {
      final dirPath = _activeDirPath ?? Directory.systemTemp.path;
      final fileName =
          _activeFileName ?? 'interceptly_${_sessionId}_session.tmp';
      await _writerIsolate.restart(
        tempDirPath: dirPath,
        fileName: fileName,
      );
      if (_isDisposed) return;
      _isRespawning = false;

      while (true) {
        final pending = _preInitQueue.removeFirstOrNull();
        if (pending == null) break;
        _sendCapture(pending);
      }
    } catch (error, stackTrace) {
      if (_isDisposed) return;
      if (kDebugMode) {
        debugPrint(
          '[Interceptly] isolate respawn failed: $error\n$stackTrace',
        );
      }
      _enterFallbackMode();
    } finally {
      _isRespawning = false;
    }
  }

  int _computeCaptureBytes(RawCapture capture) {
    final req = capture.requestSizeBytes ?? 0;
    final res = capture.responseSizeBytes ?? 0;
    final total = req + res;
    if (total > 0) return total;
    return capture.url.length + 256;
  }

  /// Enqueues a capture directly to isolate or pre-init queue (zero allocation).
  void record(RawCapture capture) {
    if (_isDisposed) return;

    if (_initFailed || _fallbackMode) {
      _processInMemory(capture);
      return;
    }

    if (!_initialized) {
      _preInitQueue.add(capture);
      initialize();
      return;
    }

    if (_isRespawning || !_writerIsolate.isReady) {
      _preInitQueue.add(capture);
      return;
    }

    _sendCapture(capture);
  }

  void _sendCapture(RawCapture capture) {
    if (_inFlight >= _settings.maxQueuedEvents ||
        _inFlightBytes >= maxInFlightBytes) {
      _droppedCount++;
      return;
    }
    final captureBytes = _computeCaptureBytes(capture);
    _inFlight++;
    _inFlightBytes += captureBytes;
    _sentBytes[capture.id] = captureBytes;
    _sentGenerations[capture.id] = _generation;

    final sent = _writerIsolate.send(capture);
    if (!sent) {
      _inFlight--;
      final rem = _inFlightBytes - captureBytes;
      _inFlightBytes = rem > 0 ? rem : 0;
      _sentBytes.remove(capture.id);
      _sentGenerations.remove(capture.id);
      _preInitQueue.add(capture);
    }
  }

  void _handleEntryReady(IndexEntry entry) {
    if (_inFlight > 0) {
      _inFlight--;
    }
    final bytes = _sentBytes.remove(entry.id) ?? 0;
    final rem = _inFlightBytes - bytes;
    _inFlightBytes = rem > 0 ? rem : 0;

    if (entry.fileRotationCount != null &&
        entry.fileRotationCount! > _fileRotationCount) {
      _fileRotationCount = entry.fileRotationCount!;
    }

    _onEntryReceived?.call(entry.id);
    final sentGeneration = _sentGenerations.remove(entry.id);
    if (sentGeneration != _generation) {
      return;
    }
    _onEntryReady(entry);
  }

  /// Clears queue and counters synchronously when isolate is not initialized.
  void clearSync() {
    _preInitQueue.clear();
    _droppedCount = 0;
    _generation++;
    _sentGenerations.clear();
    _sentBytes.clear();
    _inFlight = 0;
    _inFlightBytes = 0;
  }

  /// Clears in-flight and queued items, bumping generation to drop stale entries.
  Future<void> clear() async {
    clearSync();
    if (_initialized && !_fallbackMode) {
      await _writerIsolate.clear();
      clearSync();
    }
  }

  /// Disposes background writer isolate and associated stream subscriptions.
  Future<void> dispose() async {
    _isDisposed = true;
    _preInitQueue.clear();
    await _eventSub?.cancel();
    _eventSub = null;
    await _resultSub?.cancel();
    _resultSub = null;
    await _writerIsolate.dispose();
    _tempFilePath = null;
    _initialized = false;
    _sentGenerations.clear();
    _sentBytes.clear();
    _inFlight = 0;
    _inFlightBytes = 0;
    _initFuture = null;
    _isRespawning = false;
  }
}
