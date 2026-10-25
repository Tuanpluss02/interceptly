import 'dart:typed_data';

/// Immutable context tracking an ongoing HTTP request capture lifecycle.
class HttpRequestContext {
  /// Creates an immutable [HttpRequestContext].
  const HttpRequestContext({
    required this.id,
    required this.method,
    required this.uri,
    required this.startedAt,
    this.requestHeaders = const {},
    this.requestBodyBytes,
    this.requestContentType,
    this.captureGeneration,
  });

  /// Unique identifier for this request lifecycle.
  final String id;

  /// HTTP method (e.g. GET, POST, PUT, DELETE).
  final String method;

  /// Target URI for this request.
  final Uri uri;

  /// Wall-clock time when the request was initiated.
  final DateTime startedAt;

  /// HTTP headers sent with the request.
  final Map<String, String> requestHeaders;

  /// Captured raw request body bytes, if available.
  final Uint8List? requestBodyBytes;

  /// Content-Type header of the request body, if available.
  final String? requestContentType;

  /// Generation fence captured when this request was initiated.
  final int? captureGeneration;

  /// String representation of [uri].
  String get url => uri.toString();

  /// Creates a copy of this context with updated properties.
  HttpRequestContext copyWith({
    String? method,
    Uri? uri,
    Map<String, String>? requestHeaders,
    Uint8List? requestBodyBytes,
    String? requestContentType,
    int? captureGeneration,
  }) {
    return HttpRequestContext(
      id: id,
      method: method ?? this.method,
      uri: uri ?? this.uri,
      startedAt: startedAt,
      requestHeaders: requestHeaders ?? this.requestHeaders,
      requestBodyBytes: requestBodyBytes ?? this.requestBodyBytes,
      requestContentType: requestContentType ?? this.requestContentType,
      captureGeneration: captureGeneration ?? this.captureGeneration,
    );
  }
}
