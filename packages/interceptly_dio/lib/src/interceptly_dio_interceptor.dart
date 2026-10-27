import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:interceptly/adapter.dart';

/// A Dio interceptor that captures requests and responses for Interceptly.
class InterceptlyDioInterceptor extends Interceptor {
  /// Creates an interceptor backed by [collector].
  InterceptlyDioInterceptor([
    HttpTrafficCollector? collector,
  ]) : collector = collector ?? HttpTrafficCollector.instance;

  /// The traffic collector coordinating capture.
  final HttpTrafficCollector collector;

  static const String _scopeKey = 'interceptly_http_scope';

  /// Captures a pending request and applies pre-request simulation.
  ///
  /// Snapshots request headers so later mutations cannot alias captured state.
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!collector.shouldCapture(options.uri)) {
      handler.next(options);
      return;
    }

    final reqBytes = guardCapture(
      () => _toBytes(options.data, options.contentType),
    );

    try {
      final scope = await collector.begin(
        method: options.method,
        uri: options.uri,
        headers: normalizeHeaders(Map.of(options.headers)),
        bodyBytes: reqBytes,
        contentType: options.contentType,
      );
      if (scope.isActive) {
        options.extra[_scopeKey] = scope;
      }
    } on SimulatedNetworkException catch (e) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: e,
          message: e.toString(),
        ),
      );
      return;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Interceptly] startRequest capture failed: $e\n$st');
      }
    }

    handler.next(options);
  }

  /// Captures a successful response and applies post-response simulation.
  ///
  /// Sizes throttling from encoded body bytes so Map JSON throttles. The
  /// captured request remains the original outbound tuple; redirect
  /// destinations are not substituted into it.
  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final scope =
        response.requestOptions.extra.remove(_scopeKey) as HttpCaptureScope?;

    if (scope == null &&
        !collector.shouldCapture(response.requestOptions.uri)) {
      handler.next(response);
      return;
    }

    final effectiveScope = scope ??
        HttpCaptureScope(
          collector: collector,
          context: HttpRequestContext(
            id: RequestId.generate(),
            method: response.requestOptions.method,
            uri: response.requestOptions.uri,
            startedAt: DateTime.now(),
            requestHeaders:
                normalizeHeaders(Map.of(response.requestOptions.headers)),
          ),
        );
    response.requestOptions.extra.remove('interceptly_http_context');
    response.requestOptions.extra.remove('interceptly_req_bytes');

    final resContentType = response.headers.value(Headers.contentTypeHeader);

    if (response.data is ResponseBody) {
      final responseBody = response.data as ResponseBody;
      final boundStream = effectiveScope.bindResponseStream(
        responseBody.stream,
        statusCode: response.statusCode ?? 200,
        headers: normalizeHeaders(response.headers.map),
        contentType: resContentType,
      );
      responseBody.stream = boundStream.map(
        (chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
      );
      handler.next(response);
      return;
    }

    final resBytes =
        guardCapture(() => _toBytes(response.data, resContentType));

    var contentLength = resBytes?.length ?? 0;
    if (contentLength <= 0) {
      final contentLengthHeader =
          response.headers.value(Headers.contentLengthHeader);
      if (contentLengthHeader != null) {
        contentLength = int.tryParse(contentLengthHeader) ?? 0;
      }
    }

    try {
      final delay = collector.delayForChunk(contentLength);
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
    } catch (_) {}

    handler.next(response);

    final durationMs = effectiveScope.startedAt != null
        ? DateTime.now().difference(effectiveScope.startedAt!).inMilliseconds
        : null;
    final statusCode = response.statusCode ?? 200;
    final headers = normalizeHeaders(response.headers.map);

    unawaited(
      guardCaptureAsync(() async {
        await effectiveScope.complete(
          statusCode: statusCode,
          headers: headers,
          bodyBytes: resBytes,
          contentType: resContentType,
          durationMs: durationMs,
        );
      }),
    );
  }

  /// Captures a Dio failure response or transport error.
  ///
  /// The captured request remains the original outbound tuple; redirect
  /// destinations are not substituted into it.
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.error is SimulatedNetworkException) {
      handler.next(err);
      return;
    }

    final scope =
        err.requestOptions.extra.remove(_scopeKey) as HttpCaptureScope?;

    if (scope == null && !collector.shouldCapture(err.requestOptions.uri)) {
      handler.next(err);
      return;
    }

    final effectiveScope = scope ??
        HttpCaptureScope(
          collector: collector,
          context: HttpRequestContext(
            id: RequestId.generate(),
            method: err.requestOptions.method,
            uri: err.requestOptions.uri,
            startedAt: DateTime.now(),
            requestHeaders:
                normalizeHeaders(Map.of(err.requestOptions.headers)),
          ),
        );
    err.requestOptions.extra.remove('interceptly_http_context');
    err.requestOptions.extra.remove('interceptly_req_bytes');

    final response = err.response;
    if (err.type == DioExceptionType.badResponse && response != null) {
      final resContentType = response.headers.value(Headers.contentTypeHeader);
      final resBytes =
          guardCapture(() => _toBytes(response.data, resContentType));
      unawaited(
        guardCaptureAsync(() async {
          await effectiveScope.complete(
            statusCode: response.statusCode ?? 0,
            headers: normalizeHeaders(response.headers.map),
            bodyBytes: resBytes,
            contentType: resContentType,
          );
        }),
      );
    } else {
      if (collector.shouldCapture(err.requestOptions.uri)) {
        guardCapture(() {
          effectiveScope.amendRequest(
            method: err.requestOptions.method,
            uri: err.requestOptions.uri,
            headers: normalizeHeaders(Map.of(err.requestOptions.headers)),
          );
        });
      }
      final resContentType = response?.headers.value(Headers.contentTypeHeader);
      final responseBodyBytes = response != null
          ? guardCapture(() => _toBytes(response.data, resContentType))
          : null;
      final responseHeaders =
          response != null ? normalizeHeaders(response.headers.map) : null;

      effectiveScope.fail(
        err.error ?? err,
        errorType: err.type.name,
        errorMessage: err.message ?? err.error?.toString(),
        statusCode: response?.statusCode,
        responseHeaders: responseHeaders,
        responseBodyBytes: responseBodyBytes,
      );
    }

    handler.next(err);
  }

  /// Converts request/response data to raw bytes for capture synchronously.
  static Uint8List? _toBytes(Object? data, [String? contentType]) {
    if (data == null) return null;

    if (data is ResponseBody) {
      return utf8.encode('[streamed response]');
    }

    if (data is FormData) {
      return summarizeMultipart(
        fields: data.fields,
        files: data.files.map(
          (e) => MultipartFileInfo(
            field: e.key,
            filename: e.value.filename,
            contentType: e.value.contentType?.mimeType,
            length: e.value.length,
          ),
        ),
      );
    }

    return encodeBodyBytes(data);
  }
}
