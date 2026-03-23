import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import '../model/body_location.dart';
import '../model/index_entry.dart';
import '../model/interceptly_settings.dart';
import '../model/raw_capture.dart';
import 'body_store.dart';

// ---------------------------------------------------------------------------
// Messages sent between main isolate ↔ writer isolate
// ---------------------------------------------------------------------------

class _InitMessage {
  const _InitMessage({
    required this.replyPort,
    required this.settings,
    required this.tempDirPath,
  });

  final SendPort replyPort;
  final InterceptlySettings settings;

  /// Pre-resolved temp directory path from the main isolate.
  ///
  /// Must NOT call getTemporaryDirectory() inside the isolate — platform
  /// channels are not available in background isolates without additional setup.
  final String tempDirPath;
}

class _WriteMessage {
  const _WriteMessage({required this.capture});
  final RawCapture capture;
}

class _ClearMessage {
  const _ClearMessage();
}

class _ClearAck {
  const _ClearAck();
}

class _DisposeMessage {
  const _DisposeMessage();
}

// ---------------------------------------------------------------------------
// WriterIsolate
// ---------------------------------------------------------------------------

/// Manages a dedicated [Isolate] that processes [RawCapture]s one-at-a-time.
///
/// All [BodyStore] appends are serialised through this isolate, preventing
/// race conditions on file offsets when many requests arrive simultaneously.
class WriterIsolate {
  WriterIsolate(this._settings);

  final InterceptlySettings _settings;

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  Completer<void>? _clearCompleter;

  final StreamController<IndexEntry> _resultController =
      StreamController<IndexEntry>.broadcast();

  /// Stream of [IndexEntry]s produced after each successful write.
  Stream<IndexEntry> get results => _resultController.stream;

  /// Spawns the background isolate.
  ///
  /// [tempDirPath] must be resolved on the main isolate before calling this.
  Future<void> start({required String tempDirPath}) async {
    _receivePort = ReceivePort();

    final completer = Completer<SendPort>();

    // Single listener handles both the initial SendPort handshake and all
    // subsequent IndexEntry replies — no subscription dance needed.
    _receivePort!.listen((message) {
      if (message is SendPort && !completer.isCompleted) {
        completer.complete(message);
      } else if (message is IndexEntry) {
        _resultController.add(message);
      } else if (message is _ClearAck) {
        _clearCompleter?.complete();
        _clearCompleter = null;
      }
    });

    _isolate = await Isolate.spawn(
      _isolateEntry,
      _InitMessage(
        replyPort: _receivePort!.sendPort,
        settings: _settings,
        tempDirPath: tempDirPath,
      ),
    );

    _sendPort = await completer.future;
  }

  /// Fire-and-forget: enqueue a capture for background processing.
  void send(RawCapture capture) {
    _sendPort?.send(_WriteMessage(capture: capture));
  }

  /// Sends a clear request and waits for the isolate to confirm the file has
  /// been reset. Completes only after all previously queued writes are done.
  Future<void> clear() async {
    if (_sendPort == null) return;
    final completer = Completer<void>();
    _clearCompleter = completer;
    _sendPort!.send(const _ClearMessage());
    await completer.future;
  }

  Future<void> dispose() async {
    // Unblock any in-progress clear so its awaiter doesn't hang.
    if (_clearCompleter != null && !_clearCompleter!.isCompleted) {
      _clearCompleter!.complete();
    }
    _clearCompleter = null;
    _sendPort?.send(const _DisposeMessage());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
    await _resultController.close();
  }
}

// ---------------------------------------------------------------------------
// Isolate entry point (runs in the background isolate)
// ---------------------------------------------------------------------------

Future<void> _isolateEntry(_InitMessage init) async {
  final receivePort = ReceivePort();
  init.replyPort.send(receivePort.sendPort);

  final settings = init.settings;
  final bodyStore = BodyStore();

  // Use the pre-resolved path — no platform channel call inside the isolate.
  await bodyStore.initForWrite(init.tempDirPath);

  await for (final message in receivePort) {
    if (message is _WriteMessage) {
      final entry = await _processCapture(
        message.capture,
        bodyStore,
        settings,
      );
      init.replyPort.send(entry);
    } else if (message is _ClearMessage) {
      await bodyStore.resetFile(init.tempDirPath);
      init.replyPort.send(const _ClearAck());
    } else if (message is _DisposeMessage) {
      await bodyStore.dispose();
      break;
    }
  }
}

Future<IndexEntry> _processCapture(
  RawCapture capture,
  BodyStore bodyStore,
  InterceptlySettings settings,
) async {
  final threshold = settings.bodyOffloadThreshold;
  final maxBody = settings.maxBodyBytes;
  final previewLen = settings.previewTruncationBytes;

  final reqRaw = capture.requestBodyBytes?.materialize().asUint8List();
  final resRaw = capture.responseBodyBytes?.materialize().asUint8List();

  final reqSize = reqRaw?.length ?? 0;
  final resSize = resRaw?.length ?? 0;

  final largestSize = reqSize > resSize ? reqSize : resSize;
  final useFile = largestSize >= threshold;

  Uint8List? inlineReq;
  Uint8List? inlineRes;
  int? fileOffset;
  int? fileLength;
  bool isTruncated = false;

  if (!useFile) {
    inlineReq = _maybeTruncate(reqRaw, maxBody, previewLen);
    inlineRes = _maybeTruncate(resRaw, maxBody, previewLen);
    isTruncated = (reqRaw != null && reqRaw.length > maxBody) ||
        (resRaw != null && resRaw.length > maxBody);
  } else {
    final packed = _packBodies(reqRaw, resRaw, maxBody, previewLen);
    isTruncated = packed.truncated;
    final result = await bodyStore.append(packed.bytes);
    fileOffset = result.$1;
    fileLength = result.$2;
  }

  return IndexEntry(
    id: capture.id,
    method: capture.method,
    url: capture.url,
    statusCode: capture.statusCode,
    durationMs: capture.durationMs,
    requestSizeBytes: reqSize,
    responseSizeBytes: resSize,
    timestamp: capture.timestamp,
    hasError: capture.hasError,
    bodyLocation: useFile ? BodyLocation.file : BodyLocation.memory,
    inlineRequestBody: inlineReq,
    inlineResponseBody: inlineRes,
    requestHeaders: capture.requestHeaders,
    responseHeaders: capture.responseHeaders,
    requestContentType: capture.requestContentType,
    responseContentType: capture.responseContentType,
    errorType: capture.errorType,
    errorMessage: capture.errorMessage,
    isBodyTruncated: isTruncated,
    fileOffset: fileOffset,
    fileLength: fileLength,
  );
}

Uint8List? _maybeTruncate(Uint8List? bytes, int maxBytes, int previewLen) {
  if (bytes == null || bytes.isEmpty) return null;
  if (bytes.length <= maxBytes) return bytes;
  return bytes.sublist(
      0, previewLen < bytes.length ? previewLen : bytes.length);
}

class _PackedBodies {
  const _PackedBodies({required this.bytes, required this.truncated});
  final Uint8List bytes;
  final bool truncated;
}

_PackedBodies _packBodies(
  Uint8List? req,
  Uint8List? res,
  int maxBody,
  int previewLen,
) {
  bool truncated = false;

  Uint8List truncate(Uint8List bytes) {
    if (bytes.length <= maxBody) return bytes;
    truncated = true;
    return bytes.sublist(
        0, previewLen < bytes.length ? previewLen : bytes.length);
  }

  final reqData = req != null && req.isNotEmpty ? truncate(req) : null;
  final resData = res != null && res.isNotEmpty ? truncate(res) : null;

  final map = <String, Object?>{
    'req': reqData != null ? base64.encode(reqData) : null,
    'res': resData != null ? base64.encode(resData) : null,
    'truncated': truncated,
  };

  final encoded = utf8.encode(jsonEncode(map));
  return _PackedBodies(
      bytes: Uint8List.fromList(encoded), truncated: truncated);
}
