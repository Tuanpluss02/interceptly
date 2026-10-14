import 'dart:async';
import 'dart:typed_data';

import '../capture/capture_guard.dart';
import '../capture/stream_capture.dart';
import 'http_request_context.dart';
import 'http_traffic_collector.dart';

/// Scope managing the capture lifecycle of an individual HTTP request-response exchange.
///
/// Guaranteed to be safe, idempotent, and non-intrusive:
/// - Errors during capture are swallowed and never escape to host applications.
/// - Once settled via [complete] or [fail], subsequent completion calls are no-ops.
/// - Response streams can be bound via [bindResponseStream] for automatic chunk teeing and throttling.
class HttpCaptureScope {
  /// Creates an active [HttpCaptureScope] associated with [context].
  HttpCaptureScope({
    required this.collector,
    required HttpRequestContext? context,
  }) : _context = context;

  /// Inactive scope used when capture is disabled or initiation failed.
  factory HttpCaptureScope.inactive([HttpTrafficCollector? collector]) =>
      HttpCaptureScope(
        collector: collector ?? DefaultHttpTrafficCollector(),
        context: null,
      );

  /// The collector coordinating storage and simulation.
  final HttpTrafficCollector collector;

  HttpRequestContext? _context;
  bool _isSettled = false;

  /// Whether this scope is actively tracking an ongoing request.
  bool get isActive => _context != null;

  /// Whether this exchange has completed or failed.
  bool get isSettled => _isSettled;

  /// The immutable request context.
  HttpRequestContext? get context => _context;

  /// Unique identifier of the tracked request, if active.
  String? get id => _context?.id;

  /// HTTP method of the request, if active.
  String? get method => _context?.method;

  /// Target URI of the request, if active.
  Uri? get uri => _context?.uri;

  /// Wall-clock initiation timestamp, if active.
  DateTime? get startedAt => _context?.startedAt;

  /// Amends initial request parameters if modified downstream by an interceptor.
  void amendRequest({
    String? method,
    Uri? uri,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    String? contentType,
  }) {
    if (_isSettled || _context == null) return;
    _context = _context!.copyWith(
      method: method,
      uri: uri,
      requestHeaders: headers,
      requestBodyBytes: bodyBytes,
      requestContentType: contentType,
    );
  }

  /// Records a completed HTTP response. Safe and idempotent.
  Future<void> complete({
    required int statusCode,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    String? contentType,
    int? durationMs,
  }) async {
    if (_isSettled || _context == null) return;
    _isSettled = true;

    await guardCaptureAsync(() async {
      await collector.completeResponse(
        context: _context!,
        statusCode: statusCode,
        headers: headers,
        bodyBytes: bodyBytes,
        responseContentType: contentType,
        durationMs: durationMs,
      );
    });
  }

  /// Records a failed HTTP request (transport error, simulation failure, or cancellation).
  /// Safe and idempotent.
  void fail(
    Object error, {
    StackTrace? stackTrace,
    String? errorType,
    String? errorMessage,
    int? statusCode,
    Map<String, String>? responseHeaders,
    Uint8List? responseBodyBytes,
    int? durationMs,
  }) {
    if (_isSettled || _context == null) return;
    _isSettled = true;

    guardCapture(() {
      collector.failRequest(
        context: _context!,
        error: error,
        errorType: errorType ?? error.runtimeType.toString(),
        errorMessage: errorMessage ?? error.toString(),
        statusCode: statusCode,
        responseHeaders: responseHeaders,
        responseBodyBytes: responseBodyBytes,
        durationMs: durationMs,
      );
    });
  }

  /// Binds this scope to a streaming response, capturing chunks up to [collector.maxBodyBytes],
  /// applying simulation delays if enabled, and automatically settling with [complete] or [fail].
  Stream<List<int>> bindResponseStream(
    Stream<List<int>> responseStream, {
    required int statusCode,
    Map<String, String>? headers,
    String? contentType,
  }) {
    if (!isActive) return responseStream;

    return teeStreamCapture(
      responseStream,
      maxBytes: collector.maxBodyBytes,
      chunkDelay: collector.delayForChunk,
      onDone: (captured) {
        unawaited(
          complete(
            statusCode: statusCode,
            headers: headers,
            bodyBytes: captured,
            contentType: contentType,
          ),
        );
      },
      onError: (error, st, captured) {
        fail(
          error,
          stackTrace: st,
          statusCode: statusCode,
          responseHeaders: headers,
          responseBodyBytes: captured,
        );
      },
      onCancel: (captured) {
        fail(
          'CancellationException',
          errorType: 'CancellationException',
          errorMessage: 'Stream subscription was canceled by client.',
          statusCode: statusCode,
          responseHeaders: headers,
          responseBodyBytes: captured,
        );
      },
    );
  }
}
