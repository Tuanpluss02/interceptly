import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Append-only binary store for realtime payloads backed by an isolated temporary file.
///
/// Features:
/// - FIFO async sequential write queue ensuring zero offset races across concurrent connections.
/// - Generational rotation tracking ([rotationCount]) to detect when payloads have expired.
/// - Isolated lifecycle independent from REST storage.
@internal
class RealtimeBodyStore {
  /// Default temporary file name for realtime traffic.
  static const String kDefaultFileName = 'interceptly_realtime.tmp';

  /// Default maximum file size before automatic rotation occurs (50 MB).
  static const int kDefaultMaxFileBytes = 50 * 1024 * 1024;

  /// Default queue saturation limit for backpressure before fallback to memory occurs.
  static const int kDefaultMaxPendingWrites = 1000;

  RealtimeBodyStore({
    int maxFileBytes = kDefaultMaxFileBytes,
    int maxPendingWrites = kDefaultMaxPendingWrites,
  })  : _maxFileBytes = maxFileBytes,
        _maxPendingWrites = maxPendingWrites;

  final int _maxFileBytes;
  final int _maxPendingWrites;
  late File _file;
  RandomAccessFile? _raf;
  int _currentOffset = 0;
  int _rotationCount = 0;
  int _pendingWrites = 0;
  bool _isInitialized = false;
  bool _isDisposed = false;

  Future<void>? _writeChain;

  Future<void>? _initFuture;

  /// Current byte offset in the active file.
  int get currentOffset => _currentOffset;

  /// Number of times the file has rotated due to reaching [maxFileBytes].
  int get rotationCount => _rotationCount;

  /// Number of write operations currently queued in the FIFO async backlog.
  int get pendingWrites => _pendingWrites;

  /// Maximum number of queued write operations permitted before backpressure triggers.
  int get maxPendingWrites => _maxPendingWrites;

  /// Maximum byte capacity before rotation occurs.
  int get maxFileBytes => _maxFileBytes;

  /// Whether the store has been initialized for writing.
  bool get isInitialized => _isInitialized && !_isDisposed;

  /// Underlying file path if initialized.
  String? get filePath => _isInitialized ? _file.path : null;

  /// Opens or recreates the temp file for append-only writing.
  Future<void> initForWrite(
    String dirPath, {
    String fileName = kDefaultFileName,
  }) {
    if (_isDisposed || _isInitialized) return Future<void>.value();
    return _initFuture ??= _performInitForWrite(dirPath, fileName: fileName);
  }

  Future<void> _performInitForWrite(
    String dirPath, {
    String fileName = kDefaultFileName,
  }) async {
    if (_isDisposed || _isInitialized) return;
    _file = File('$dirPath/$fileName');
    if (await _file.exists()) {
      await _file.delete();
    }
    await _file.create(recursive: true);
    _raf = await _file.open(mode: FileMode.writeOnlyAppend);
    if (_isDisposed) {
      await _raf?.close();
      _raf = null;
      return;
    }
    _currentOffset = 0;
    _rotationCount = 0;
    _isInitialized = true;
  }

  /// Appends [bytes] to the store through the sequential FIFO async queue.
  ///
  /// Returns a record of `(fileOffset, fileLength, rotationCount)`.
  Future<(int offset, int length, int rotationCount)> append(Uint8List bytes) {
    if (!_isInitialized || _raf == null || _isDisposed) {
      throw StateError(
        'RealtimeBodyStore is not initialized for writing. Call initForWrite() first.',
      );
    }
    if (_pendingWrites >= _maxPendingWrites) {
      throw StateError(
        'RealtimeBodyStore write queue saturated (backpressure limit $_maxPendingWrites exceeded).',
      );
    }

    _pendingWrites++;
    final completer = Completer<(int, int, int)>();
    Future<void> writeOp(_) async {
      try {
        if (_isDisposed || _raf == null) {
          completer.completeError(
            StateError(
                'RealtimeBodyStore was disposed before write completed.'),
          );
          return;
        }
        if (_currentOffset + bytes.length > _maxFileBytes) {
          await _performRotate();
        }
        final offset = _currentOffset;
        final length = bytes.length;
        await _raf!.writeFrom(bytes);
        _currentOffset += length;
        completer.complete((offset, length, _rotationCount));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _pendingWrites--;
      }
    }

    final prev = _writeChain;
    if (prev == null) {
      _writeChain = writeOp(null);
    } else {
      _writeChain = prev.then(writeOp);
    }

    return completer.future;
  }

  /// Reads [length] bytes starting at [offset] from the store file.
  ///
  /// Enqueued on the FIFO [_writeChain] to avoid torn reads during
  /// concurrent rotate or reset operations. Captures the rotation count
  /// at call time and fails with a [FileSystemException] when the file
  /// rotates before or during the read so callers can emit an expired
  /// placeholder instead of new-session bytes.
  Future<Uint8List> readBytes(int offset, int length) {
    if (!_isInitialized || _isDisposed) {
      throw StateError('RealtimeBodyStore is not initialized.');
    }
    final rotBefore = _rotationCount;
    final completer = Completer<Uint8List>();
    Future<void> readOp(_) async {
      try {
        if (_rotationCount != rotBefore) {
          completer.completeError(
            const FileSystemException('rotated mid-read'),
          );
          return;
        }
        if (!_isInitialized || _isDisposed || _raf == null) {
          completer.completeError(
            StateError('RealtimeBodyStore is not initialized.'),
          );
          return;
        }
        final readRaf = await _file.open(mode: FileMode.read);
        try {
          await readRaf.setPosition(offset);
          final data = await readRaf.read(length);
          if (_rotationCount != rotBefore) {
            completer.completeError(
              const FileSystemException('rotated mid-read'),
            );
            return;
          }
          completer.complete(data);
        } finally {
          await readRaf.close();
        }
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }

    final prev = _writeChain;
    if (prev == null) {
      _writeChain = readOp(null);
    } else {
      _writeChain = prev.then(readOp);
    }
    return completer.future;
  }

  /// Explicitly rotates the store file, resetting offset to 0 and incrementing [rotationCount].
  Future<void> rotate() {
    final completer = Completer<void>();
    Future<void> rotateOp(_) async {
      try {
        await _performRotate();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }

    final prev = _writeChain;
    if (prev == null) {
      _writeChain = rotateOp(null);
    } else {
      _writeChain = prev.then(rotateOp);
    }
    return completer.future;
  }

  Future<void> _performRotate() async {
    try {
      await _raf?.flush();
    } catch (_) {}
    await _raf?.close();
    _raf = null;
    _currentOffset = 0;
    _rotationCount++;
    try {
      if (await _file.exists()) {
        await _file.delete();
      }
      await _file.create(recursive: true);
      _raf = await _file.open(mode: FileMode.writeOnlyAppend);
    } catch (_) {}
  }

  /// Resets the file on disk: deletes, recreates, and resets offset while
  /// advancing the rotation generation so prior offsets never alias new bytes.
  Future<void> resetFile(String dirPath, {String? fileName}) {
    final completer = Completer<void>();
    Future<void> resetOp(_) async {
      try {
        try {
          await _raf?.flush();
        } catch (_) {}
        await _raf?.close();
        _raf = null;
        _currentOffset = 0;
        _rotationCount++;
        final effectiveName =
            fileName ?? _file.path.split(RegExp(r'[/\\]')).last;
        _file = File('$dirPath/$effectiveName');
        if (await _file.exists()) {
          await _file.delete();
        }
        await _file.create(recursive: true);
        _raf = await _file.open(mode: FileMode.writeOnlyAppend);
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }

    final prev = _writeChain;
    if (prev == null) {
      _writeChain = resetOp(null);
    } else {
      _writeChain = prev.then(resetOp);
    }
    return completer.future;
  }

  /// Waits for all currently enqueued write/rotate/reset operations to complete.
  Future<void> flush() async {
    while (true) {
      final current = _writeChain;
      if (current == null) break;
      await current;
      if (identical(_writeChain, current)) break;
    }
    await _raf?.flush();
  }

  /// Closes the write handle, flushes pending operations, and deletes the temporary file.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    final chain = _writeChain;
    if (chain != null) {
      try {
        await chain;
      } catch (_) {}
    }

    try {
      await _raf?.flush();
    } catch (_) {}
    await _raf?.close();
    _raf = null;
    _initFuture = null;

    if (_isInitialized) {
      _isInitialized = false;
      try {
        if (await _file.exists()) {
          await _file.delete();
        }
      } catch (_) {}
    }
  }
}
