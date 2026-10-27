import 'package:flutter/foundation.dart';

import '../capture/capture_guard.dart';
import '../engine/capture_generation.dart';
import '../model/network_simulation.dart';
import '../model/raw_capture.dart';
import '../engine/interceptly_engine.dart';
import '../engine/request_id.dart';
import 'http_capture_scope.dart';
import 'http_request_context.dart';

/// Contract for coordinating HTTP traffic capture lifecycle events.
///
/// Implementations handle pending record creation, network simulation,
/// duration calculation, and finalized capture recording into an [InterceptlyEngine].
abstract interface class HttpTrafficCollector {
  static HttpTrafficCollector? _instance;

  /// The active global [HttpTrafficCollector] instance.
  static HttpTrafficCollector get instance =>
      _instance ??= DefaultHttpTrafficCollector();

  /// Overrides the global [HttpTrafficCollector] instance (e.g. for testing).
  static set instance(HttpTrafficCollector collector) {
    _instance = collector;
  }

  /// Maximum byte capacity for captured request/response bodies.
  int get maxBodyBytes;

  /// Calculates simulated throughput delay for streaming response chunks.
  Duration delayForChunk(int chunkBytes);

  /// Whether traffic to [uri] should be captured under the current session settings.
  bool shouldCapture(Uri? uri);

  /// Initiates an HTTP exchange capture, returning an [HttpCaptureScope].
  ///
  /// Throws [SimulatedNetworkException] if pre-request simulation rejects the request.
  Future<HttpCaptureScope> begin({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    String? contentType,
    String? requestId,
  });

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
    int? responseSizeBytes,
    int? durationMs,
    String? responseContentType,
    bool? responseTruncatedAtStorage,
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
    int? responseSizeBytes,
    int? durationMs,
    bool? responseTruncatedAtStorage,
  });
}

/// Default implementation of [HttpTrafficCollector] backed by [InterceptlyEngine].
class DefaultHttpTrafficCollector implements HttpTrafficCollector {
  /// Creates a collector backed by [engine] or [InterceptlyEngine.instance].
  DefaultHttpTrafficCollector({InterceptlyEngine? engine})
      : _customEngine = engine;

  final InterceptlyEngine? _customEngine;

  /// The underlying [InterceptlyEngine] used for storing captured traffic.
  InterceptlyEngine get engine => _customEngine ?? InterceptlyEngine.instance;

  @override
  int get maxBodyBytes => engine.settings.maxBodyBytes;

  @override
  Duration delayForChunk(int chunkBytes) =>
      engine.throughputDelayForChunk(chunkBytes);

  @override
  bool shouldCapture(Uri? uri) {
    if (!engine.isEnabled) return false;
    if (uri == null) return true;
    final predicate = engine.settings.shouldCapture;
    if (predicate == null) return true;
    try {
      return predicate(uri.toString());
    } catch (_) {
      return true;
    }
  }

  @override
  Future<HttpCaptureScope> begin({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    String? contentType,
    String? requestId,
  }) async {
    final context = await startRequest(
      method: method,
      uri: uri,
      headers: headers,
      bodyBytes: bodyBytes,
      contentType: contentType,
      requestId: requestId,
    );
    return HttpCaptureScope(collector: this, context: context);
  }

  @override
  Future<HttpRequestContext?> startRequest({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    String? contentType,
    String? requestId,
  }) async {
    if (!shouldCapture(uri)) {
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
      attachCaptureGeneration(context, engine.httpGeneration);

      guardCapture(() {
        engine.recordPending(
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
        await engine.applyNetworkSimulationBeforeRequest(
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
    int? responseSizeBytes,
    int? durationMs,
    String? responseContentType,
    bool? responseTruncatedAtStorage,
  }) async {
    await guardCaptureAsync(() async {
      final parsedLen = _parseContentLength(headers);
      final rawLen = bodyBytes?.length ?? 0;
      final int actualResponseSize = responseSizeBytes ?? parsedLen ?? rawLen;
      final bool isResponseTruncated;

      if (responseTruncatedAtStorage != null) {
        isResponseTruncated = responseTruncatedAtStorage;
      } else {
        isResponseTruncated = maxBodyBytes > 0 &&
            (rawLen > maxBodyBytes ||
                (parsedLen != null &&
                    parsedLen > maxBodyBytes &&
                    rawLen >= maxBodyBytes));
      }

      if (durationMs == null) {
        await engine.applyNetworkSimulationAfterResponse(
          downloadBytes: actualResponseSize,
        );
      }

      final elapsed = durationMs ??
          DateTime.now().difference(context.startedAt).inMilliseconds;
      final resolvedContentType = responseContentType ??
          (headers != null ? headerValue(headers, 'content-type') : null);

      final reqBytes = context.requestBodyBytes;
      final reqSize = reqBytes?.length;
      final isRequestTruncated =
          maxBodyBytes > 0 && (reqSize ?? 0) > maxBodyBytes;

      final capture = RawCapture(
        id: context.id,
        method: context.method,
        url: context.uri.toString(),
        requestHeaders: context.requestHeaders,
        responseHeaders: headers ?? const {},
        statusCode: statusCode,
        durationMs: elapsed < 0 ? 0 : elapsed,
        timestamp: context.startedAt,
        requestBodyBytes: RawCapture.wrapBytes(reqBytes, maxBodyBytes),
        responseBodyBytes: RawCapture.wrapBytes(bodyBytes, maxBodyBytes),
        requestSizeBytes: reqSize,
        responseSizeBytes: actualResponseSize,
        requestContentType: context.requestContentType,
        responseContentType: resolvedContentType,
        requestTruncatedAtStorage: isRequestTruncated,
        responseTruncatedAtStorage: isResponseTruncated,
      );
      attachCaptureGeneration(capture, readCaptureGeneration(context));

      engine.record(capture);
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
    int? responseSizeBytes,
    int? durationMs,
    bool? responseTruncatedAtStorage,
  }) {
    guardCapture(() {
      final elapsed = durationMs ??
          DateTime.now().difference(context.startedAt).inMilliseconds;
      final resolvedContentType = responseHeaders != null
          ? headerValue(responseHeaders, 'content-type')
          : null;

      final parsedLen = _parseContentLength(responseHeaders);
      final rawLen = responseBodyBytes?.length ?? 0;
      final int actualResponseSize = responseSizeBytes ?? parsedLen ?? rawLen;
      final bool isResponseTruncated;

      if (responseTruncatedAtStorage != null) {
        isResponseTruncated = responseTruncatedAtStorage;
      } else {
        isResponseTruncated = maxBodyBytes > 0 &&
            (rawLen > maxBodyBytes ||
                (parsedLen != null &&
                    parsedLen > maxBodyBytes &&
                    rawLen >= maxBodyBytes));
      }

      final reqBytes = context.requestBodyBytes;
      final reqSize = reqBytes?.length;
      final isRequestTruncated =
          maxBodyBytes > 0 && (reqSize ?? 0) > maxBodyBytes;

      final capture = RawCapture(
        id: context.id,
        method: context.method,
        url: context.uri.toString(),
        requestHeaders: context.requestHeaders,
        responseHeaders: responseHeaders ?? const {},
        statusCode: statusCode ?? 0,
        durationMs: elapsed < 0 ? 0 : elapsed,
        timestamp: context.startedAt,
        requestBodyBytes: RawCapture.wrapBytes(reqBytes, maxBodyBytes),
        responseBodyBytes:
            RawCapture.wrapBytes(responseBodyBytes, maxBodyBytes),
        requestSizeBytes: reqSize,
        responseSizeBytes: actualResponseSize,
        requestContentType: context.requestContentType,
        responseContentType: resolvedContentType,
        errorType: errorType ?? error.runtimeType.toString(),
        errorMessage: errorMessage ?? error.toString(),
        requestTruncatedAtStorage: isRequestTruncated,
        responseTruncatedAtStorage: isResponseTruncated,
      );
      attachCaptureGeneration(capture, readCaptureGeneration(context));

      engine.record(capture);
    });
  }

  static int? _parseContentLength(Map<String, String>? headers) {
    if (headers == null) return null;
    final cl = headerValue(headers, 'content-length');
    if (cl == null) return null;
    final parsed = int.tryParse(cl);
    return (parsed != null && parsed >= 0) ? parsed : null;
  }
}
