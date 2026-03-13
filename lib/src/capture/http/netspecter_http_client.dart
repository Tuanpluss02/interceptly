import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../model/raw_capture.dart';
import '../../storage/inspector_session.dart';

/// A drop-in [http.BaseClient] wrapper that captures all requests.
///
/// Usage:
/// ```dart
/// final client = NetSpecterHttpClient(http.Client());
/// // or
/// final client = NetSpecterHttpClient.wrap(http.Client());
/// ```
class NetSpecterHttpClient extends http.BaseClient {
  NetSpecterHttpClient(
    this._inner, [
    InspectorSession? session,
  ]) : session = session ?? InspectorSession.instance;

  factory NetSpecterHttpClient.wrap(
    http.Client inner, [
    InspectorSession? session,
  ]) =>
      NetSpecterHttpClient(inner, session);

  final http.Client _inner;
  final InspectorSession session;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final startedAt = DateTime.now();

    // Materialise the body bytes before forwarding so we can capture them.
    final bodyBytes = request is http.Request
        ? Uint8List.fromList(request.bodyBytes)
        : null;

    final response = await _inner.send(request);

    // Buffer the response stream so we can capture the body without
    // affecting the caller — return a new stream with the same bytes.
    final responseBytes = await response.stream.toBytes();
    final durationMs = DateTime.now().difference(startedAt).inMilliseconds;

    final reqHeaders = Map<String, String>.fromEntries(
      request.headers.entries.map((e) => MapEntry(e.key, e.value)),
    );
    final resHeaders = Map<String, String>.fromEntries(
      response.headers.entries.map((e) => MapEntry(e.key, e.value)),
    );

    final capture = RawCapture(
      id: id,
      method: request.method,
      url: request.url.toString(),
      requestHeaders: reqHeaders,
      responseHeaders: resHeaders,
      statusCode: response.statusCode,
      durationMs: durationMs,
      timestamp: startedAt,
      requestBodyBytes: RawCapture.wrapBytes(bodyBytes),
      responseBodyBytes: RawCapture.wrapBytes(
        Uint8List.fromList(responseBytes),
      ),
      requestContentType: request.headers['content-type'],
      responseContentType: response.headers['content-type'],
    );

    session.record(capture);

    return http.StreamedResponse(
      Stream.value(responseBytes),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();

}
