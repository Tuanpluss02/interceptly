import 'dart:typed_data';

import 'body_location.dart';

/// Lightweight record that lives entirely in RAM.
///
/// The list view reads only from [IndexEntry]s — zero file I/O on scroll.
/// Full body data is accessed on demand via [InspectorSession.loadDetail].
class IndexEntry {
  const IndexEntry({
    required this.id,
    required this.method,
    required this.url,
    required this.statusCode,
    required this.durationMs,
    required this.requestSizeBytes,
    required this.responseSizeBytes,
    required this.timestamp,
    required this.hasError,
    required this.bodyLocation,
    this.inlineRequestBody,
    this.inlineResponseBody,
    this.requestHeaders = const {},
    this.responseHeaders = const {},
    this.requestContentType,
    this.responseContentType,
    this.errorType,
    this.errorMessage,
    this.isBodyTruncated = false,
    this.fileOffset,
    this.fileLength,
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

  /// Where the full body lives.
  final BodyLocation bodyLocation;

  /// Non-null when [bodyLocation] == [BodyLocation.memory].
  final Uint8List? inlineRequestBody;
  final Uint8List? inlineResponseBody;

  /// Headers stored inline for the detail view (small data).
  final Map<String, String> requestHeaders;
  final Map<String, String> responseHeaders;
  final String? requestContentType;
  final String? responseContentType;

  /// Non-null when [hasError] is true.
  final String? errorType;
  final String? errorMessage;

  /// True if any body was truncated due to exceeding the size limit.
  final bool isBodyTruncated;

  /// Non-null when [bodyLocation] == [BodyLocation.file].
  final int? fileOffset;
  final int? fileLength;
}
