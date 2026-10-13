import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:interceptly/interceptly.dart';

/// A drop-in [http.BaseClient] wrapper that captures all requests.
///
/// Usage:
/// ```dart
/// final client = InterceptlyHttpClient(http.Client());
/// // or
/// final client = InterceptlyHttpClient.wrap(http.Client());
/// ```
class InterceptlyHttpClient extends http.BaseClient
    implements HttpCaptureAdapter {
  InterceptlyHttpClient(
    this._inner, [
    InspectorSession? session,
    HttpTrafficCollector? collector,
  ])  : session = session ??
            (collector is DefaultHttpTrafficCollector
                ? collector.session
                : InspectorSession.instance),
        collector = collector ??
            DefaultHttpTrafficCollector(
              session ?? InspectorSession.instance,
            );

  factory InterceptlyHttpClient.wrap(
    http.Client inner, [
    InspectorSession? session,
    HttpTrafficCollector? collector,
  ]) =>
      InterceptlyHttpClient(inner, session, collector);

  final http.Client _inner;

  @override
  final InspectorSession session;

  @override
  final HttpTrafficCollector collector;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = _extractRequestBody(request);

    final reqHeaders = Map<String, String>.fromEntries(
      request.headers.entries.map((e) => MapEntry(e.key, e.value)),
    );

    HttpRequestContext? context;
    try {
      context = await collector.startRequest(
        method: request.method,
        uri: request.url,
        headers: reqHeaders,
        bodyBytes: bodyBytes,
        contentType: request.headers['content-type'],
      );
    } on SimulatedNetworkException {
      rethrow;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Interceptly] startRequest capture failed: $e\n$st');
      }
    }

    http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (e) {
      if (context != null) {
        collector.failRequest(
          context: context,
          error: e,
          errorType: e.runtimeType.toString(),
          errorMessage: e.toString(),
        );
      }
      rethrow;
    }

    final resHeaders = Map<String, String>.fromEntries(
      response.headers.entries.map((e) => MapEntry(e.key, e.value)),
    );

    return http.StreamedResponse(
      _teeResponseStream(
        source: response.stream,
        context: context,
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
  /// [collector.completeResponse] is called once when the stream ends successfully,
  /// and [collector.failRequest] when it encounters an error or cancellation.
  Stream<List<int>> _teeResponseStream({
    required Stream<List<int>> source,
    required HttpRequestContext? context,
    required http.StreamedResponse response,
    required Map<String, String> resHeaders,
  }) {
    final maxCapture = session.settings.maxBodyBytes;
    final captureBuffer = BytesBuilder();
    bool captureStopped = false;
    bool recorded = false;

    void recordResponse() {
      if (recorded || context == null) return;
      recorded = true;
      final captured = captureBuffer.isEmpty ? null : captureBuffer.toBytes();
      guardCapture(() {
        unawaited(
          collector.completeResponse(
            context: context,
            statusCode: response.statusCode,
            headers: resHeaders,
            bodyBytes: captured,
            responseContentType: response.headers['content-type'],
          ),
        );
      });
    }

    void recordFailure({
      required Object error,
      String? errorType,
      String? errorMessage,
    }) {
      if (recorded || context == null) return;
      recorded = true;
      final captured = captureBuffer.isEmpty ? null : captureBuffer.toBytes();
      guardCapture(() {
        collector.failRequest(
          context: context,
          error: error,
          errorType: errorType,
          errorMessage: errorMessage,
          statusCode: response.statusCode,
          responseHeaders: resHeaders,
          responseBodyBytes: captured,
        );
      });
    }

    late StreamSubscription<List<int>> sub;
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () {
        void handleChunk(List<int> chunk) {
          if (recorded || controller.isClosed) return;
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
        }

        sub = source.listen(
          (chunk) {
            final delay = session.throughputDelayForChunk(chunk.length);
            if (delay > Duration.zero) {
              sub.pause();
              Future<void>.delayed(delay, () {
                handleChunk(chunk);
                if (!controller.isClosed) sub.resume();
              });
              return;
            }
            handleChunk(chunk);
          },
          onDone: () {
            recordResponse();
            controller.close();
          },
          onError: (Object e, StackTrace st) {
            recordFailure(
              error: e,
              errorType: e.runtimeType.toString(),
              errorMessage: e.toString(),
            );
            controller.addError(e, st);
            controller.close();
          },
          cancelOnError: false,
        );
      },
      onPause: () => sub.pause(),
      onResume: () => sub.resume(),
      onCancel: () {
        recordFailure(
          error: 'CancellationException',
          errorType: 'CancellationException',
          errorMessage: 'Stream subscription was canceled by client.',
        );
        return sub.cancel();
      },
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
