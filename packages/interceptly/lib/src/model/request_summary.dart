import 'body_truncation.dart';

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
    required this.requestTruncation,
    required this.responseTruncation,
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

  /// What survived of the request body, and where it was cut.
  final BodyTruncation requestTruncation;

  /// What survived of the response body, and where it was cut.
  final BodyTruncation responseTruncation;

  /// True when either body lost bytes that cannot be reproduced.
  bool get hasDataLoss =>
      requestTruncation.hasDataLoss || responseTruncation.hasDataLoss;

  /// True when either body is shorter than what the network actually sent.
  bool get isTruncated =>
      requestTruncation.isTruncated || responseTruncation.isTruncated;

  final Map<String, String> requestHeaders;
  final Map<String, String> responseHeaders;
  final String? requestContentType;
  final String? responseContentType;

  /// Non-null when [hasError] is true.
  final String? errorType;
  final String? errorMessage;

  /// Whether this request represents a realtime connection (WebSocket, Socket.IO, SSE).
  bool get isRealtime => method == 'WS' || method == 'SIO' || method == 'SSE';
}
