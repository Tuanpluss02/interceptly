import 'dart:typed_data';

import 'body_truncation.dart';

/// Full detail model — loaded on demand when user opens a request.
///
/// Built by [InspectorSession.loadDetail] from a [RequestSummary].
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
    this.requestBodyBytes,
    this.responseBodyBytes,
    this.requestTruncation = const BodyTruncation.complete(0),
    this.responseTruncation = const BodyTruncation.complete(0),
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

  /// UTF-8 decoded body text, or a `[binary: N bytes]` placeholder for non-text content.
  final String? requestBodyPreview;
  final String? responseBodyPreview;

  /// Complete un-truncated raw request bytes, if available.
  final Uint8List? requestBodyBytes;

  /// Complete un-truncated raw response bytes, if available.
  final Uint8List? responseBodyBytes;

  /// What survived of the request body, and where it was cut.
  final BodyTruncation requestTruncation;

  /// What survived of the response body, and where it was cut.
  final BodyTruncation responseTruncation;

  final String? errorType;
  final String? errorMessage;

  bool get hasError => errorType != null;

  /// True when either body lost bytes that cannot be reproduced.
  bool get hasDataLoss =>
      requestTruncation.hasDataLoss || responseTruncation.hasDataLoss;

  /// True when either body is shorter than what the network actually sent.
  bool get isTruncated =>
      requestTruncation.isTruncated || responseTruncation.isTruncated;
}
