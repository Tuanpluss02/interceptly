import 'dart:async';
import 'dart:typed_data';

import 'capture_guard.dart';

/// An in-memory buffer that retains up to [maxBytes] bytes from streaming data.
class CappedBytesBuilder {
  /// Creates a [CappedBytesBuilder] limited to [maxBytes].
  ///
  /// If [maxBytes] is non-positive, capacity is unbounded.
  CappedBytesBuilder(this.maxBytes);

  /// Maximum number of bytes to retain.
  final int maxBytes;

  final BytesBuilder _builder = BytesBuilder();
  int _totalBytes = 0;
  bool _isCapped = false;

  /// Total number of bytes passed to [add], including truncated bytes.
  int get totalBytes => _totalBytes;

  /// True if the stream produced more bytes than [maxBytes].
  bool get isTruncated => _isCapped;

  /// Adds a [chunk] to the buffer, truncating if [maxBytes] is reached.
  void add(List<int> chunk) {
    _totalBytes += chunk.length;
    if (_isCapped) return;

    if (maxBytes <= 0) {
      _builder.add(chunk);
      return;
    }

    final remaining = maxBytes - _builder.length;
    if (chunk.length <= remaining) {
      _builder.add(chunk);
    } else {
      if (remaining > 0) {
        _builder.add(chunk.sublist(0, remaining));
      }
      _isCapped = true;
    }
  }

  /// Returns the accumulated bytes, or null if nothing was added.
  Uint8List? toBytesOrNull() {
    return _builder.isEmpty ? null : _builder.toBytes();
  }
}

/// Tees [source] into a new stream that:
/// - Immediately forwards every chunk to listeners,
/// - Accumulates up to [maxBytes] into a [CappedBytesBuilder] for traffic inspection,
/// - Delays chunk delivery if [chunkDelay] produces a duration (for network simulation),
/// - Calls exactly one termination callback ([onDone], [onError], or [onCancel]) with captured bytes.
Stream<List<int>> teeStreamCapture(
  Stream<List<int>> source, {
  required int maxBytes,
  Duration Function(int chunkBytes)? chunkDelay,
  required void Function(Uint8List? captured) onDone,
  required void Function(
          Object error, StackTrace stackTrace, Uint8List? captured)
      onError,
  required void Function(Uint8List? captured) onCancel,
}) {
  final buffer = CappedBytesBuilder(maxBytes);
  bool settled = false;
  bool isCanceled = false;

  late StreamSubscription<List<int>> sub;
  late final StreamController<List<int>> controller;

  void finishDone() {
    if (settled) return;
    settled = true;
    final captured = buffer.toBytesOrNull();
    guardCapture(() => onDone(captured));
  }

  void finishError(Object error, StackTrace st) {
    if (settled) return;
    settled = true;
    final captured = buffer.toBytesOrNull();
    guardCapture(() => onError(error, st, captured));
  }

  void finishCancel() {
    if (settled) return;
    settled = true;
    final captured = buffer.toBytesOrNull();
    guardCapture(() => onCancel(captured));
  }

  controller = StreamController<List<int>>(
    onListen: () {
      void handleChunk(List<int> chunk) {
        if (settled || controller.isClosed) return;
        controller.add(chunk);
        buffer.add(chunk);
      }

      sub = source.listen(
        (chunk) {
          final delay = chunkDelay?.call(chunk.length) ?? Duration.zero;
          if (delay > Duration.zero) {
            try {
              if (!isCanceled) sub.pause();
            } catch (_) {}
            Future<void>.delayed(delay, () {
              handleChunk(chunk);
              if (!controller.isClosed && !isCanceled) {
                try {
                  if (sub.isPaused) {
                    sub.resume();
                  }
                } catch (_) {}
              }
            });
            return;
          }
          handleChunk(chunk);
        },
        onDone: () {
          finishDone();
          controller.close();
        },
        onError: (Object e, StackTrace st) {
          finishError(e, st);
          controller.addError(e, st);
          controller.close();
        },
        cancelOnError: false,
      );
    },
    onPause: () {
      if (!isCanceled) {
        try {
          sub.pause();
        } catch (_) {}
      }
    },
    onResume: () {
      if (!isCanceled) {
        try {
          if (sub.isPaused) {
            sub.resume();
          }
        } catch (_) {}
      }
    },
    onCancel: () {
      isCanceled = true;
      finishCancel();
      return sub.cancel();
    },
  );

  return controller.stream;
}
