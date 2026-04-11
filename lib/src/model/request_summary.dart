/// Public-facing summary of a captured request, safe to expose on the
/// app-developer API.
///
/// Does not contain storage internals (body location, file offsets, inline
/// byte buffers). Use [InspectorSession.loadDetail] to retrieve full body data.
class RequestSummary {
  const RequestSummary({
    required this.id,
    required this.method,
    required this.url,
    required this.statusCode,
    required this.durationMs,
    required this.requestSizeBytes,
    required this.responseSizeBytes,
    required this.timestamp,
    required this.hasError,
    required this.isBodyTruncated,
    this.requestHeaders = const {},
    this.responseHeaders = const {},
    this.requestContentType,
    this.responseContentType,
    this.errorType,
    this.errorMessage,
  });

  final String id;
  final String method;
  final String url;

  /// 0 = pending/error (no response yet).
  final int statusCode;
  final int durationMs;
  final int requestSizeBytes;
  final int responseSizeBytes;
  final DateTime timestamp;
  final bool hasError;

  /// True if any body was truncated due to exceeding the size limit.
  final bool isBodyTruncated;

  final Map<String, String> requestHeaders;
  final Map<String, String> responseHeaders;
  final String? requestContentType;
  final String? responseContentType;

  /// Non-null when [hasError] is true.
  final String? errorType;
  final String? errorMessage;
}
