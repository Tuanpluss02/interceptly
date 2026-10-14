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

  Future<void>? _initFuture;
  bool _initialized = false;
  int _inFlight = 0;
  int _droppedCount = 0;
  int _generation = 0;
  final Map<String, int> _sentGenerations = {};
  String? _tempFilePath;

  /// Whether the pipeline has finished asynchronous isolate initialization.
  bool get isInitialized => _initialized;

  /// Pre-resolved temporary file path used for body offloading on disk.
  String? get tempFilePath => _tempFilePath;

  /// Number of captures dropped due to queue saturation or isolate failure.
  int get droppedCount =>
      _droppedCount + (_initialized ? 0 : _preInitQueue.droppedCount);

  /// Number of captures currently dispatched to the writer isolate.
  int get inFlight => _inFlight;

  /// Current generation number for fence verification.
  int get generation => _generation;

  /// Updates settings propagated from session reconfiguration.
  void updateSettings(InterceptlySettings newSettings) {
    _settings = newSettings;
    _writerIsolate.updateSettings(newSettings);
    _preInitQueue.updateMaxSize(newSettings.maxQueuedEvents);
  }

  /// Initializes disk storage and boots the background writer isolate.
  Future<void> initialize() async {
    _initFuture ??= _performInit();
    return _initFuture;
  }

  Future<void> _performInit() async {
    if (_initialized) return;

    try {
      final String dirPath;
      final fileName = 'interceptly_${_sessionId}_session.tmp';
      if (_settings.persistToDisk) {
        final dir = await getTemporaryDirectory();
        dirPath = dir.path;
        _tempFilePath = '$dirPath/$fileName';

        await BodyStore.purgeOrphanedTempFiles(
          dirPath,
          currentFileName: fileName,
          maxAge: const Duration(hours: 24),
        );
      } else {
        dirPath = Directory.systemTemp.path;
      }

      await _writerIsolate.start(tempDirPath: dirPath, fileName: fileName);
      _resultSub = _writerIsolate.results.listen(_handleEntryReady);
      _initialized = true;

      _droppedCount += _preInitQueue.droppedCount;
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

  /// Enqueues a capture directly to isolate or pre-init queue (zero allocation).
  void record(RawCapture capture) {
    if (!_initialized) {
      _preInitQueue.add(capture);
      initialize().catchError((Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint(
            '[Interceptly] background init failed: $error\n$stackTrace',
          );
        }
      });
      return;
    }
    _sendCapture(capture);
  }

  void _sendCapture(RawCapture capture) {
    if (_inFlight >= _settings.maxQueuedEvents) {
      _droppedCount++;
      return;
    }
    _inFlight++;
    _sentGenerations[capture.id] = _generation;
    try {
      _writerIsolate.send(capture);
    } catch (_) {
      _inFlight--;
      _sentGenerations.remove(capture.id);
      _droppedCount++;
    }
  }

  void _handleEntryReady(IndexEntry entry) {
    if (_inFlight > 0) {
      _inFlight--;
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
    _inFlight = 0;
  }

  /// Clears in-flight and queued items, bumping generation to drop stale entries.
  Future<void> clear() async {
    if (_initialized) {
      await _writerIsolate.clear();
    } else {
      clearSync();
      return;
    }
    _droppedCount = 0;
    _generation++;
    _sentGenerations.clear();
    _inFlight = 0;
  }

  /// Disposes background writer isolate and associated stream subscriptions.
  Future<void> dispose() async {
    _preInitQueue.clear();
    await _resultSub?.cancel();
    _resultSub = null;
    await _writerIsolate.dispose();
    _tempFilePath = null;
    _initialized = false;
    _sentGenerations.clear();
    _inFlight = 0;
    _initFuture = null;
  }
}
