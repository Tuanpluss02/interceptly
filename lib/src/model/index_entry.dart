import 'dart:typed_data';

import 'body_location.dart';
import 'request_summary.dart';

/// Internal record that extends [RequestSummary] with storage metadata.
///
/// Lives entirely in RAM. The list view reads only from [IndexEntry]s —
/// zero file I/O on scroll. Full body data is accessed on demand via
/// [InspectorSession.loadDetail].
class IndexEntry extends RequestSummary {
  const IndexEntry({
    required super.id,
    required super.method,
    required super.url,
    required super.statusCode,
    required super.durationMs,
    required super.requestSizeBytes,
    required super.responseSizeBytes,
    required super.timestamp,
    required super.hasError,
    required super.isBodyTruncated,
    super.requestHeaders = const {},
    super.responseHeaders = const {},
    super.requestContentType,
    super.responseContentType,
    super.errorType,
    super.errorMessage,
    required this.bodyLocation,
    this.inlineRequestBody,
    this.inlineResponseBody,
    this.fileOffset,
    this.fileLength,
  });

  /// Where the full body lives.
  final BodyLocation bodyLocation;

  /// Non-null when [bodyLocation] == [BodyLocation.memory].
  final Uint8List? inlineRequestBody;
  final Uint8List? inlineResponseBody;

  /// Non-null when [bodyLocation] == [BodyLocation.file].
  final int? fileOffset;
  final int? fileLength;
}
