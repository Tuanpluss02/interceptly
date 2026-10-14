import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../model/body_location.dart';
import '../model/body_truncation.dart';
import '../model/index_entry.dart';
import '../model/interceptly_settings.dart';
import '../model/raw_capture.dart';
import 'body_store.dart';

class _InitMessage {
  const _InitMessage({
    required this.replyPort,
    required this.tempDirPath,
    this.fileName = BodyStore.kFileName,
    this.maxFileBytes = BodyStore.kMaxFileBytes,
  });

  final SendPort replyPort;

  /// Pre-resolved temp directory path from the main isolate.
  ///
  /// Must NOT call getTemporaryDirectory() inside the isolate — platform
  /// channels are not available in background isolates without additional setup.
  final String tempDirPath;
  final String fileName;
  final int maxFileBytes;
}

class _WriteMessage {
  const _WriteMessage({
    required this.capture,
    required this.bodyOffloadThreshold,
    required this.maxBodyBytes,
    this.persistToDisk = true,
  });

  final RawCapture capture;

  /// Storage tunables snapshotted when the capture was recorded, so the
  /// background isolate stays stateless and always honors current settings.
  final int bodyOffloadThreshold;
  final int maxBodyBytes;
  final bool persistToDisk;
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

class _DisposeAck {
  const _DisposeAck();
}

/// Manages a dedicated [Isolate] that processes [RawCapture]s one-at-a-time.
///
/// All [BodyStore] appends are serialised through this isolate, preventing
/// race conditions on file offsets when many requests arrive simultaneously.
///
/// The isolate itself is stateless with respect to configuration: every write
/// message carries the storage tunables in effect when the capture was
/// recorded, so reconfiguring settings never leaves stale limits behind and
/// no settings object ever needs to cross isolate boundaries.
class WriterIsolate {
  WriterIsolate(this._settings);

  InterceptlySettings _settings;

  /// Refreshes the settings stamped onto subsequently recorded captures.
  void updateSettings(InterceptlySettings settings) {
    _settings = settings;
  }

  String? _activeTempFilePath;
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  ReceivePort? _errorPort;
  ReceivePort? _exitPort;
  Completer<void>? _clearCompleter;
  Completer<void>? _disposeCompleter;

  final StreamController<IndexEntry> _resultController =
      StreamController<IndexEntry>.broadcast();

  /// Stream of [IndexEntry]s produced after each successful write.
  Stream<IndexEntry> get results => _resultController.stream;

  /// Spawns the background isolate.
  ///
  /// [tempDirPath] must be resolved on the main isolate before calling this.
  Future<void> start({
    required String tempDirPath,
    String fileName = BodyStore.kFileName,
    int maxFileBytes = BodyStore.kMaxFileBytes,
  }) async {
    _activeTempFilePath = '$tempDirPath/$fileName';
    _receivePort = ReceivePort();
    _errorPort = ReceivePort();
    _exitPort = ReceivePort();

    final completer = Completer<SendPort>();

    _receivePort!.listen((message) {
      if (message is SendPort && !completer.isCompleted) {
        completer.complete(message);
      } else if (message is IndexEntry) {
        _resultController.add(message);
      } else if (message is _ClearAck) {
        _clearCompleter?.complete();
        _clearCompleter = null;
      } else if (message is _DisposeAck) {
        _disposeCompleter?.complete();
        _disposeCompleter = null;
      }
    });

    _errorPort!.listen((error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
      _clearCompleter?.complete();
      _clearCompleter = null;
      _disposeCompleter?.complete();
      _disposeCompleter = null;
    });

    _exitPort!.listen((_) {
      _clearCompleter?.complete();
      _clearCompleter = null;
      _disposeCompleter?.complete();
      _disposeCompleter = null;
    });

    _isolate = await Isolate.spawn(
      _isolateEntry,
      _InitMessage(
        replyPort: _receivePort!.sendPort,
        tempDirPath: tempDirPath,
        fileName: fileName,
        maxFileBytes: maxFileBytes,
      ),
      onError: _errorPort!.sendPort,
      onExit: _exitPort!.sendPort,
    );

    _sendPort = await completer.future;
  }

  /// Fire-and-forget: enqueue a capture for background processing.
  void send(RawCapture capture) {
    _sendPort?.send(_WriteMessage(
      capture: capture,
      bodyOffloadThreshold: _settings.bodyOffloadThreshold,
      maxBodyBytes: _settings.maxBodyBytes,
      persistToDisk: _settings.persistToDisk,
    ));
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
    if (_clearCompleter != null && !_clearCompleter!.isCompleted) {
      _clearCompleter!.complete();
    }
    _clearCompleter = null;
    if (_sendPort != null) {
      final completer = Completer<void>();
      _disposeCompleter = completer;
      _sendPort!.send(const _DisposeMessage());
      try {
        await completer.future.timeout(const Duration(milliseconds: 500));
      } catch (_) {}
    }
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
    _errorPort?.close();
    _errorPort = null;
    _exitPort?.close();
    _exitPort = null;
    await _resultController.close();

    final filePath = _activeTempFilePath;
    _activeTempFilePath = null;
    if (filePath != null) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }
}

Future<void> _isolateEntry(_InitMessage init) async {
  final receivePort = ReceivePort();
  init.replyPort.send(receivePort.sendPort);

  final bodyStore = BodyStore(maxFileBytes: init.maxFileBytes);

  try {
    await bodyStore.initForWrite(init.tempDirPath, fileName: init.fileName);
  } catch (_) {}

  await for (final message in receivePort) {
    try {
      if (message is _WriteMessage) {
        final entry = await _processCapture(
          message.capture,
          bodyStore,
          message.bodyOffloadThreshold,
          message.maxBodyBytes,
          persistToDisk: message.persistToDisk,
        );
        init.replyPort.send(entry);
      } else if (message is _ClearMessage) {
        try {
          await bodyStore.resetFile(init.tempDirPath, fileName: init.fileName);
        } catch (_) {}
        init.replyPort.send(const _ClearAck());
      } else if (message is _DisposeMessage) {
        try {
          await bodyStore.dispose();
        } catch (_) {}
        init.replyPort.send(const _DisposeAck());
        break;
      }
    } catch (_) {
      if (message is _WriteMessage) {
        init.replyPort.send(_fallbackEntry(message.capture));
      }
    }
  }
}

IndexEntry _fallbackEntry(RawCapture capture) {
  return IndexEntry(
    id: capture.id,
    method: capture.method,
    url: capture.url,
    statusCode: capture.statusCode,
    durationMs: capture.durationMs,
    requestSizeBytes: 0,
    responseSizeBytes: 0,
    timestamp: capture.timestamp,
    hasError: capture.hasError,
    bodyLocation: BodyLocation.memory,
    inlineRequestBody: null,
    inlineResponseBody: null,
    requestHeaders: capture.requestHeaders,
    responseHeaders: capture.responseHeaders,
    requestContentType: capture.requestContentType,
    responseContentType: capture.responseContentType,
    errorType: capture.errorType,
    errorMessage: capture.errorMessage,
    requestTruncation: const BodyTruncation.complete(0),
    responseTruncation: const BodyTruncation.complete(0),
    fileOffset: null,
    fileLength: null,
  );
}

/// Outcome of packing both bodies for the on-disk record.
///
/// The trailing flag byte keeps the packed format byte-compatible with
/// earlier sessions; the per-side booleans are derived from the same limits
/// when the entry is built, so they are not carried here.
typedef _PackedBodies = ({Uint8List bytes});

/// Builds the [BodyTruncation] for one body given how many bytes storage kept.
///
/// `maxBody <= 0` means unlimited, matching [InterceptlySettings.maxBodyBytes].
BodyTruncation _storageTruncation(
  int originalBytes,
  int maxBody,
  int keptBytes,
) {
  if (maxBody <= 0 || originalBytes <= keptBytes) {
    return BodyTruncation.complete(originalBytes);
  }
  return BodyTruncation(
    originalBytes: originalBytes,
    retainedBytes: keptBytes,
    stage: TruncationStage.storage,
  );
}

Future<IndexEntry> _processCapture(
  RawCapture capture,
  BodyStore bodyStore,
  int threshold,
  int maxBody, {
  bool persistToDisk = true,
}) async {
  final reqRaw = capture.requestBodyBytes?.materialize().asUint8List();
  final resRaw = capture.responseBodyBytes?.materialize().asUint8List();

  final reqSize = reqRaw?.length ?? 0;
  final resSize = resRaw?.length ?? 0;

  final largestSize = reqSize > resSize ? reqSize : resSize;
  var useFile = persistToDisk && largestSize >= threshold;

  Uint8List? inlineReq;
  Uint8List? inlineRes;
  int? fileOffset;
  int? fileLength;

  if (useFile) {
    try {
      final packed = _packBodies(reqRaw, resRaw, maxBody);
      final result = await bodyStore.append(packed.bytes);
      fileOffset = result.$1;
      fileLength = result.$2;
    } catch (_) {
      useFile = false;
    }
  }

  if (!useFile) {
    inlineReq = _maybeTruncate(reqRaw, maxBody);
    inlineRes = _maybeTruncate(resRaw, maxBody);
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
    requestTruncation: _storageTruncation(
      reqSize,
      maxBody,
      _keptBytes(reqSize, maxBody),
    ),
    responseTruncation: _storageTruncation(
      resSize,
      maxBody,
      _keptBytes(resSize, maxBody),
    ),
    fileOffset: fileOffset,
    fileLength: fileLength,
  );
}

Uint8List? _maybeTruncate(Uint8List? bytes, int maxBytes) {
  if (bytes == null || bytes.isEmpty) return null;
  if (maxBytes <= 0 || bytes.length <= maxBytes) return bytes;
  return bytes.sublist(0, maxBytes);
}

int _keptBytes(int originalBytes, int maxBody) =>
    maxBody > 0 && originalBytes > maxBody ? maxBody : originalBytes;

_PackedBodies _packBodies(
  Uint8List? req,
  Uint8List? res,
  int maxBody,
) {
  Uint8List? truncate(Uint8List bytes) {
    if (maxBody <= 0 || bytes.length <= maxBody) return bytes;
    return bytes.sublist(0, maxBody);
  }

  final reqTruncated = maxBody > 0 && req != null && req.length > maxBody;
  final resTruncated = maxBody > 0 && res != null && res.length > maxBody;

  final reqData = req != null && req.isNotEmpty ? truncate(req) : null;
  final resData = res != null && res.isNotEmpty ? truncate(res) : null;

  final total = 4 + (reqData?.length ?? 0) + 4 + (resData?.length ?? 0) + 1;
  final out = Uint8List(total);
  final data = ByteData.sublistView(out);
  var offset = 0;

  void writePart(Uint8List? part) {
    if (part == null) {
      data.setUint32(offset, 0xFFFFFFFF, Endian.big);
      offset += 4;
      return;
    }
    data.setUint32(offset, part.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + part.length, part);
    offset += part.length;
  }

  writePart(reqData);
  writePart(resData);
  out[offset] = (reqTruncated || resTruncated) ? 1 : 0;

  return (bytes: out);
}
