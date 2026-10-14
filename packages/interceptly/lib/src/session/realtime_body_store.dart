import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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

  RealtimeBodyStore({int maxFileBytes = kDefaultMaxFileBytes})
      : _maxFileBytes = maxFileBytes;

  final int _maxFileBytes;
  late File _file;
  RandomAccessFile? _raf;
  int _currentOffset = 0;
  int _rotationCount = 0;
  bool _isInitialized = false;
  bool _isDisposed = false;

  Future<void> _writeChain = Future<void>.value();

  /// Current byte offset in the active file.
  int get currentOffset => _currentOffset;

  /// Number of times the file has rotated due to reaching [maxFileBytes].
  int get rotationCount => _rotationCount;

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
  }) async {
    if (_isDisposed) return;
    _file = File('$dirPath/$fileName');
    if (await _file.exists()) {
      await _file.delete();
    }
    await _file.create(recursive: true);
    _raf = await _file.open(mode: FileMode.writeOnlyAppend);
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

    final completer = Completer<(int, int, int)>();
    _writeChain = _writeChain.then((_) async {
      if (_isDisposed || _raf == null) {
        completer.completeError(
          StateError('RealtimeBodyStore was disposed before write completed.'),
        );
        return;
      }
      try {
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
      }
    });

    return completer.future;
  }

  /// Reads [length] bytes starting at [offset] from the store file.
  Future<Uint8List> readBytes(int offset, int length) async {
    if (!_isInitialized || _isDisposed) {
      throw StateError('RealtimeBodyStore is not initialized.');
    }
    final readRaf = await _file.open(mode: FileMode.read);
    try {
      await readRaf.setPosition(offset);
      return await readRaf.read(length);
    } finally {
      await readRaf.close();
    }
  }

  /// Explicitly rotates the store file, resetting offset to 0 and incrementing [rotationCount].
  Future<void> rotate() {
    final completer = Completer<void>();
    _writeChain = _writeChain.then((_) async {
      try {
        await _performRotate();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _performRotate() async {
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

  /// Resets the file on disk: deletes, recreates, and resets offset/rotation.
  Future<void> resetFile(String dirPath, {String? fileName}) {
    final completer = Completer<void>();
    _writeChain = _writeChain.then((_) async {
      try {
        await _raf?.close();
        _raf = null;
        _currentOffset = 0;
        _rotationCount = 0;
        final effectiveName = fileName ?? _file.path.split(RegExp(r'[/\\]')).last;
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
    });
    return completer.future;
  }

  /// Closes the write handle, flushes pending operations, and deletes the temporary file.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    try {
      await _writeChain;
    } catch (_) {}

    await _raf?.close();
    _raf = null;
    _isInitialized = false;

    try {
      if (await _file.exists()) {
        await _file.delete();
      }
    } catch (_) {}
  }
}
