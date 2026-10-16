import 'dart:typed_data';

import 'body_location.dart';
import 'body_truncation.dart';
import 'request_filter.dart';
import 'request_summary.dart';

/// Internal record that extends [RequestSummary] with storage metadata.
///
/// Lives entirely in RAM. The list view reads only from [IndexEntry]s —
/// zero file I/O on scroll. Full body data is accessed on demand via
/// [InspectorSession.loadDetail].
class IndexEntry extends RequestSummary {
  IndexEntry({
    required super.id,
    required super.method,
    required super.url,
    required super.statusCode,
    required super.durationMs,
    required super.requestSizeBytes,
    required super.responseSizeBytes,
    required super.timestamp,
    required super.hasError,
    required super.requestTruncation,
    required super.responseTruncation,
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
    this.fileRotationCount,
    String? domain,
  }) : domain = domain ?? RequestFilter.extractDomain(url);

  /// Where the full body lives.
  final BodyLocation bodyLocation;

  /// Non-null when [bodyLocation] == [BodyLocation.memory].
  final Uint8List? inlineRequestBody;
  final Uint8List? inlineResponseBody;

  /// Non-null when [bodyLocation] == [BodyLocation.file].
  final int? fileOffset;
  final int? fileLength;

  /// Generation of the BodyStore file rotation when this entry was written.
  final int? fileRotationCount;

  /// Domain pre-parsed from [url] at creation time.
  final String domain;

  /// Returns a copy of this entry with the given fields replaced.
  IndexEntry copyWith({
    String? id,
    String? method,
    String? url,
    int? statusCode,
    int? durationMs,
    int? requestSizeBytes,
    int? responseSizeBytes,
    DateTime? timestamp,
    bool? hasError,
    BodyTruncation? requestTruncation,
    BodyTruncation? responseTruncation,
    Map<String, String>? requestHeaders,
    Map<String, String>? responseHeaders,
    String? requestContentType,
    String? responseContentType,
    String? errorType,
    String? errorMessage,
    BodyLocation? bodyLocation,
    Uint8List? inlineRequestBody,
    Uint8List? inlineResponseBody,
    int? fileOffset,
    int? fileLength,
    int? fileRotationCount,
    String? domain,
  }) {
    final effectiveUrl = url ?? this.url;
    return IndexEntry(
      id: id ?? this.id,
      method: method ?? this.method,
      url: effectiveUrl,
      statusCode: statusCode ?? this.statusCode,
      durationMs: durationMs ?? this.durationMs,
      requestSizeBytes: requestSizeBytes ?? this.requestSizeBytes,
      responseSizeBytes: responseSizeBytes ?? this.responseSizeBytes,
      timestamp: timestamp ?? this.timestamp,
      hasError: hasError ?? this.hasError,
      requestTruncation: requestTruncation ?? this.requestTruncation,
      responseTruncation: responseTruncation ?? this.responseTruncation,
      requestHeaders: requestHeaders ?? this.requestHeaders,
      responseHeaders: responseHeaders ?? this.responseHeaders,
      requestContentType: requestContentType ?? this.requestContentType,
      responseContentType: responseContentType ?? this.responseContentType,
      errorType: errorType ?? this.errorType,
      errorMessage: errorMessage ?? this.errorMessage,
      bodyLocation: bodyLocation ?? this.bodyLocation,
      inlineRequestBody: inlineRequestBody ?? this.inlineRequestBody,
      inlineResponseBody: inlineResponseBody ?? this.inlineResponseBody,
      fileOffset: fileOffset ?? this.fileOffset,
      fileLength: fileLength ?? this.fileLength,
      fileRotationCount: fileRotationCount ?? this.fileRotationCount,
      domain: domain ??
          (url != null
              ? RequestFilter.extractDomain(effectiveUrl)
              : this.domain),
    );
  }
}
