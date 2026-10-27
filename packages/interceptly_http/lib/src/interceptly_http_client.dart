import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:interceptly/adapter.dart';

/// An HTTP client exception thrown when requests are aborted due to simulated network profiles.
class InterceptlySimulatedClientException extends http.ClientException
    implements SimulatedNetworkException {
  /// Creates a simulated client exception.
  InterceptlySimulatedClientException(super.message, [super.uri]);
}

/// A drop-in [http.BaseClient] wrapper that captures requests and streaming responses for Interceptly.
///
/// Snapshots request headers on capture so later caller mutations cannot
/// alias retained traffic records.
class InterceptlyHttpClient extends http.BaseClient {
  /// Wraps [inner] with Interceptly capture.
  InterceptlyHttpClient(
    this._inner, [
    HttpTrafficCollector? collector,
  ]) : collector = collector ?? HttpTrafficCollector.instance;

  final http.Client _inner;

  /// The traffic collector coordinating capture.
  final HttpTrafficCollector collector;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!collector.shouldCapture(request.url)) {
      return _inner.send(request);
    }
    final bodyBytes = _extractRequestBody(request);

    final HttpCaptureScope scope;
    try {
      scope = await collector.begin(
        method: request.method,
        uri: request.url,
        headers: Map.of(request.headers),
        bodyBytes: bodyBytes,
        contentType: request.headers['content-type'],
      );
    } on SimulatedNetworkException catch (e) {
      throw InterceptlySimulatedClientException(e.message, request.url);
    }

    final http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (e, st) {
      scope.fail(e, stackTrace: st);
      rethrow;
    }

    return http.StreamedResponse(
      scope.bindResponseStream(
        response.stream,
        statusCode: response.statusCode,
        headers: response.headers,
        contentType: response.headers['content-type'],
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

  @override
  void close() => _inner.close();

  static Uint8List? _extractRequestBody(http.BaseRequest request) {
    if (request is http.Request) {
      return Uint8List.fromList(request.bodyBytes);
    }
    if (request is http.MultipartRequest) {
      return summarizeMultipart(
        fields: request.fields.entries,
        files: request.files.map(
          (f) => MultipartFileInfo(
            field: f.field,
            filename: f.filename,
            contentType: f.contentType.mimeType,
            length: f.length,
          ),
        ),
      );
    }
    return null;
  }
}
