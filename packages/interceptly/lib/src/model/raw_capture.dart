import 'dart:isolate';
import 'dart:typed_data';

/// Raw data captured by an interceptor and sent to the WriterIsolate.
///
/// Uses [TransferableTypedData] for body bytes to avoid copying large buffers
/// across isolate boundaries — the underlying memory is transferred, not copied.
class RawCapture {
  const RawCapture({
    required this.id,
    required this.method,
    required this.url,
    required this.requestHeaders,
    required this.responseHeaders,
    required this.statusCode,
    required this.durationMs,
    required this.timestamp,
    this.requestBodyBytes,
    this.responseBodyBytes,
    this.requestSizeBytes,
    this.responseSizeBytes,
    this.requestContentType,
    this.responseContentType,
    this.errorType,
    this.errorMessage,
    this.requestTruncatedAtStorage = false,
    this.responseTruncatedAtStorage = false,
  });

  final String id;
  final String method;
  final String url;
  final Map<String, String> requestHeaders;
  final Map<String, String> responseHeaders;
  final int statusCode;
  final int durationMs;
  final DateTime timestamp;

  /// Null when there is no body (e.g. GET with no payload).
  final TransferableTypedData? requestBodyBytes;
  final TransferableTypedData? responseBodyBytes;

  /// Original byte counts before adapter-level or network truncation, if known.
  final int? requestSizeBytes;
  final int? responseSizeBytes;

  final String? requestContentType;
  final String? responseContentType;

  /// Explicit indicators for storage truncation (exceeding maxBodyBytes).
  final bool requestTruncatedAtStorage;
  final bool responseTruncatedAtStorage;

  /// Non-null when the request failed.
  final String? errorType;
  final String? errorMessage;

  bool get hasError => errorType != null;

  /// Convenience: wrap [Uint8List] into [TransferableTypedData], optionally capping at [maxBytes].
  static TransferableTypedData? wrapBytes(Uint8List? bytes,
      [int maxBytes = 0]) {
    if (bytes == null || bytes.isEmpty) return null;
    final slice = (maxBytes > 0 && bytes.length > maxBytes)
        ? bytes.sublist(0, maxBytes)
        : bytes;
    return TransferableTypedData.fromList([slice]);
  }
}
