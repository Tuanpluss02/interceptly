import 'package:flutter/foundation.dart';

import '../capture/capture_guard.dart';
import '../model/network_simulation.dart';
import '../model/raw_capture.dart';
import '../session/inspector_session.dart';
import '../session/request_id.dart';
import 'http_request_context.dart';

/// Contract for coordinating HTTP traffic capture lifecycle events.
///
/// Implementations handle pending record creation, network simulation,
/// duration calculation, and finalized capture recording into an [InspectorSession].
abstract interface class HttpTrafficCollector {
  /// Records an initiated request and applies pre-request network simulation.
  ///
  /// Returns an [HttpRequestContext] tracking this request lifecycle, or `null`
  /// if capture is disabled or encounters an unexpected error.
  ///
  /// Throws [SimulatedNetworkException] when pre-request simulation rejects the request
  /// (e.g. offline simulation profile is active), after recording the failure.
  Future<HttpRequestContext?> startRequest({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    String? contentType,
    String? requestId,
  });

  /// Records a successfully received HTTP response and applies post-response network simulation.
  ///
  /// Safe to call: internal capture errors will never escape or break application requests.
  Future<void> completeResponse({
    required HttpRequestContext context,
    required int statusCode,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    int? durationMs,
    String? responseContentType,
  });

  /// Records a failed HTTP request (transport error, connection error, or simulation failure).
  ///
  /// Safe to call: internal capture errors will never escape or break application requests.
  void failRequest({
    required HttpRequestContext context,
    required Object error,
    String? errorType,
    String? errorMessage,
    int? statusCode,
    Map<String, String>? responseHeaders,
    Uint8List? responseBodyBytes,
    int? durationMs,
  });
}

/// Default implementation of [HttpTrafficCollector] backed by [InspectorSession].
class DefaultHttpTrafficCollector implements HttpTrafficCollector {
  /// Creates a collector backed by [session] (defaults to [InspectorSession.instance]).
  DefaultHttpTrafficCollector([InspectorSession? session])
      : _session = session ?? InspectorSession.instance;

  final InspectorSession _session;

  /// The underlying [InspectorSession] used for storing captured traffic.
  InspectorSession get session => _session;

  @override
  Future<HttpRequestContext?> startRequest({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    String? contentType,
    String? requestId,
  }) async {
    if (!_session.isEnabled) {
      return null;
    }

    try {
      final startedAt = DateTime.now();
      final id = requestId ?? RequestId.generate();
      final resolvedContentType = contentType ??
          (headers != null ? headerValue(headers, 'content-type') : null);

      final context = HttpRequestContext(
        id: id,
        method: method,
        uri: uri,
        startedAt: startedAt,
        requestHeaders: headers ?? const {},
        requestBodyBytes: bodyBytes,
        requestContentType: resolvedContentType,
      );

      guardCapture(() {
        _session.recordPending(
          id: id,
          method: method,
          url: uri.toString(),
          timestamp: startedAt,
          requestHeaders: headers ?? const {},
          requestBodyBytes: bodyBytes,
          requestContentType: resolvedContentType,
        );
      });

      try {
        await _session.applyNetworkSimulationBeforeRequest(
          uploadBytes: bodyBytes?.length ?? 0,
        );
      } on SimulatedNetworkException catch (e) {
        failRequest(
          context: context,
          error: e,
          errorType: 'SimulatedNetworkException',
          errorMessage: e.toString(),
        );
        rethrow;
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[Interceptly] pre-request simulation error: $e\n$st');
        }
      }

      return context;
    } on SimulatedNetworkException {
      rethrow;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Interceptly] startRequest error: $e\n$st');
      }
      return null;
    }
  }

  @override
  Future<void> completeResponse({
    required HttpRequestContext context,
    required int statusCode,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    int? durationMs,
    String? responseContentType,
  }) async {
    await guardCaptureAsync(() async {
      await _session.applyNetworkSimulationAfterResponse(
        downloadBytes: bodyBytes?.length ?? 0,
      );

      final elapsed = durationMs ??
          DateTime.now().difference(context.startedAt).inMilliseconds;
      final resolvedContentType = responseContentType ??
          (headers != null ? headerValue(headers, 'content-type') : null);

      final capture = RawCapture(
        id: context.id,
        method: context.method,
        url: context.uri.toString(),
        requestHeaders: context.requestHeaders,
        responseHeaders: headers ?? const {},
        statusCode: statusCode,
        durationMs: elapsed < 0 ? 0 : elapsed,
        timestamp: context.startedAt,
        requestBodyBytes: RawCapture.wrapBytes(context.requestBodyBytes),
        responseBodyBytes: RawCapture.wrapBytes(bodyBytes),
        requestContentType: context.requestContentType,
        responseContentType: resolvedContentType,
      );

      _session.record(capture);
    });
  }

  @override
  void failRequest({
    required HttpRequestContext context,
    required Object error,
    String? errorType,
    String? errorMessage,
    int? statusCode,
    Map<String, String>? responseHeaders,
    Uint8List? responseBodyBytes,
    int? durationMs,
  }) {
    guardCapture(() {
      final elapsed = durationMs ??
          DateTime.now().difference(context.startedAt).inMilliseconds;
      final resolvedContentType = responseHeaders != null
          ? headerValue(responseHeaders, 'content-type')
          : null;

      final capture = RawCapture(
        id: context.id,
        method: context.method,
        url: context.uri.toString(),
        requestHeaders: context.requestHeaders,
        responseHeaders: responseHeaders ?? const {},
        statusCode: statusCode ?? 0,
        durationMs: elapsed < 0 ? 0 : elapsed,
        timestamp: context.startedAt,
        requestBodyBytes: RawCapture.wrapBytes(context.requestBodyBytes),
        responseBodyBytes: RawCapture.wrapBytes(responseBodyBytes),
        requestContentType: context.requestContentType,
        responseContentType: resolvedContentType,
        errorType: errorType ?? error.runtimeType.toString(),
        errorMessage: errorMessage ?? error.toString(),
      );

      _session.record(capture);
    });
  }
}
