import 'dart:typed_data';

/// Full detail model — loaded on demand when user opens a request.
///
/// Built by [InspectorSession.loadDetail] from an [IndexEntry].
class RequestRecord {
  const RequestRecord({
    required this.id,
    required this.method,
    required this.url,
    required this.statusCode,
    required this.durationMs,
    required this.requestSizeBytes,
    required this.responseSizeBytes,
    required this.timestamp,
    required this.requestHeaders,
    required this.responseHeaders,
    this.requestContentType,
    this.responseContentType,
    this.requestBodyPreview,
    this.responseBodyPreview,
    this.requestBodyBytesPreview,
    this.responseBodyBytesPreview,
    this.isBodyTruncated = false,
    this.errorType,
    this.errorMessage,
  });

  final String id;
  final String method;
  final String url;
  final int statusCode;
  final int durationMs;
  final int requestSizeBytes;
  final int responseSizeBytes;
  final DateTime timestamp;
  final Map<String, String> requestHeaders;
  final Map<String, String> responseHeaders;
  final String? requestContentType;
  final String? responseContentType;

  /// UTF-8 decoded body text, or a `binary: N bytes` placeholder for non-text content.
  final String? requestBodyPreview;
  final String? responseBodyPreview;
  final Uint8List? requestBodyBytesPreview;
  final Uint8List? responseBodyBytesPreview;

  /// True if the body exceeded [NetSpecterSettings.maxBodyBytes] and was cut.
  final bool isBodyTruncated;

  final String? errorType;
  final String? errorMessage;

  bool get hasError => errorType != null;
}
