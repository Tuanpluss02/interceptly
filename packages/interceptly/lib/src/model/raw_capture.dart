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
    this.requestContentType,
    this.responseContentType,
    this.errorType,
    this.errorMessage,
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

  final String? requestContentType;
  final String? responseContentType;

  /// Non-null when the request failed.
  final String? errorType;
  final String? errorMessage;

  bool get hasError => errorType != null;

  /// Convenience: wrap [Uint8List] into [TransferableTypedData].
  static TransferableTypedData? wrapBytes(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    return TransferableTypedData.fromList([bytes]);
  }
}
