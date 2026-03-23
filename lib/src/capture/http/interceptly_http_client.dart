import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../session/request_id.dart';
import '../../model/raw_capture.dart';
import '../../session/inspector_session.dart';

/// A drop-in [http.BaseClient] wrapper that captures all requests.
///
/// Usage:
/// ```dart
/// final client = InterceptlyHttpClient(http.Client());
/// // or
/// final client = InterceptlyHttpClient.wrap(http.Client());
/// ```
class InterceptlyHttpClient extends http.BaseClient {
  InterceptlyHttpClient(
    this._inner, [
    InspectorSession? session,
  ]) : session = session ?? InspectorSession.instance;

  factory InterceptlyHttpClient.wrap(
    http.Client inner, [
    InspectorSession? session,
  ]) =>
      InterceptlyHttpClient(inner, session);

  final http.Client _inner;
  final InspectorSession session;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final id = RequestId.generate();
    final startedAt = DateTime.now();

    final bodyBytes = _extractRequestBody(request);

    final reqHeaders = Map<String, String>.fromEntries(
      request.headers.entries.map((e) => MapEntry(e.key, e.value)),
    );

    session.recordPending(
      id: id,
      method: request.method,
      url: request.url.toString(),
      timestamp: startedAt,
      requestHeaders: reqHeaders,
      requestBodyBytes: bodyBytes,
      requestContentType: request.headers['content-type'],
    );

    http.StreamedResponse response;

    try {
      await session.applyNetworkSimulationBeforeRequest(
        uploadBytes: bodyBytes?.length ?? 0,
      );
      response = await _inner.send(request);
    } catch (e) {
      final durationMs = DateTime.now().difference(startedAt).inMilliseconds;
      session.record(RawCapture(
        id: id,
        method: request.method,
        url: request.url.toString(),
        requestHeaders: reqHeaders,
        responseHeaders: const {},
        statusCode: 0,
        durationMs: durationMs,
        timestamp: startedAt,
        requestBodyBytes: RawCapture.wrapBytes(bodyBytes),
        requestContentType: request.headers['content-type'],
        errorType: e.runtimeType.toString(),
        errorMessage: e.toString(),
      ));
      rethrow;
    }

    final resHeaders = Map<String, String>.fromEntries(
      response.headers.entries.map((e) => MapEntry(e.key, e.value)),
    );

    // Tee the response stream: forward every chunk to the caller immediately
    // while accumulating up to maxBodyBytes for the inspector.
    // This preserves true streaming behaviour and prevents OOM on large files.
    return http.StreamedResponse(
      _teeResponseStream(
        source: response.stream,
        startedAt: startedAt,
        id: id,
        request: request,
        reqHeaders: reqHeaders,
        bodyBytes: bodyBytes,
        response: response,
        resHeaders: resHeaders,
      ),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  /// Tees [source] into a new stream that:
  /// - forwards every chunk to the caller unchanged and immediately, and
  /// - accumulates up to [InterceptlySettings.maxBodyBytes] bytes into a
  ///   [BytesBuilder] for capture — then stops accumulating (never buffers
  ///   more than the cap regardless of how large the response is).
  ///
  /// [session.record] is called once when the stream ends (successfully or
  /// with an error), so duration reflects the full download time.
  Stream<List<int>> _teeResponseStream({
    required Stream<List<int>> source,
    required DateTime startedAt,
    required String id,
    required http.BaseRequest request,
    required Map<String, String> reqHeaders,
    required Uint8List? bodyBytes,
    required http.StreamedResponse response,
    required Map<String, String> resHeaders,
  }) {
    final maxCapture = session.settings.maxBodyBytes;
    final captureBuffer = BytesBuilder();
    bool captureStopped = false;
    bool recorded = false;

    void record({String? errorType, String? errorMessage}) {
      if (recorded) return;
      recorded = true;
      final durationMs = DateTime.now().difference(startedAt).inMilliseconds;
      final captured = captureBuffer.isEmpty ? null : captureBuffer.toBytes();
      session.record(RawCapture(
        id: id,
        method: request.method,
        url: request.url.toString(),
        requestHeaders: reqHeaders,
        responseHeaders: resHeaders,
        statusCode: response.statusCode,
        durationMs: durationMs,
        timestamp: startedAt,
        requestBodyBytes: RawCapture.wrapBytes(bodyBytes),
        responseBodyBytes: RawCapture.wrapBytes(captured),
        requestContentType: request.headers['content-type'],
        responseContentType: response.headers['content-type'],
        errorType: errorType,
        errorMessage: errorMessage,
      ));
    }

    late StreamSubscription<List<int>> sub;
    final controller = StreamController<List<int>>(
      onPause: () => sub.pause(),
      onResume: () => sub.resume(),
      onCancel: () => sub.cancel(),
    );

    sub = source.listen(
      (chunk) {
        final delay = session.throughputDelayForChunk(chunk.length);
        if (delay > Duration.zero) {
          sub.pause();
          Future<void>.delayed(delay, () {
            controller.add(chunk);
            if (!captureStopped) {
              final remaining = maxCapture - captureBuffer.length;
              if (chunk.length <= remaining) {
                captureBuffer.add(chunk);
              } else {
                if (remaining > 0) {
                  captureBuffer.add(chunk.sublist(0, remaining));
                }
                captureStopped = true;
              }
            }
            sub.resume();
          });
          return;
        }

        controller.add(chunk);
        if (!captureStopped) {
          final remaining = maxCapture - captureBuffer.length;
          if (chunk.length <= remaining) {
            captureBuffer.add(chunk);
          } else {
            if (remaining > 0) captureBuffer.add(chunk.sublist(0, remaining));
            captureStopped = true;
          }
        }
      },
      onDone: () {
        record();
        controller.close();
      },
      onError: (Object e, StackTrace st) {
        record(errorType: e.runtimeType.toString(), errorMessage: e.toString());
        controller.addError(e, st);
        controller.close();
      },
      cancelOnError: false,
    );

    return controller.stream;
  }

  @override
  void close() => _inner.close();

  /// Extracts a human-readable body snapshot without consuming any stream.
  ///
  /// - [http.Request]: returns the already-buffered body bytes as-is.
  /// - [http.MultipartRequest]: builds a text summary of fields and file
  ///   metadata from the request's public properties — safe to call before
  ///   [send] because it never touches the underlying multipart stream.
  /// - [http.StreamedRequest] and other subtypes: returns null. Tee-ing an
  ///   arbitrary [Stream<List<int>>] would require buffering the entire upload
  ///   in memory, which is unsafe for large files.
  static Uint8List? _extractRequestBody(http.BaseRequest request) {
    if (request is http.Request) {
      return Uint8List.fromList(request.bodyBytes);
    }
    if (request is http.MultipartRequest) {
      return _summarizeMultipart(request);
    }
    return null;
  }

  static Uint8List _summarizeMultipart(http.MultipartRequest request) {
    final parts = <String>[];
    for (final entry in request.fields.entries) {
      parts.add('[field] ${entry.key}=${entry.value}');
    }
    for (final file in request.files) {
      final ct = file.contentType.mimeType;
      final size = ', ${file.length} bytes';
      final name = file.filename ?? 'blob';
      parts.add('[file] ${file.field}: $name ($ct$size)');
    }
    return utf8.encode(parts.join('\n'));
  }
}
