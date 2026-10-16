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
        headers: normalizeHeaders(options.headers),
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
  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final scope = response.requestOptions.extra.remove(_scopeKey)
        as HttpCaptureScope?;

    if (scope == null && !collector.shouldCapture(response.requestOptions.uri)) {
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
            requestHeaders: normalizeHeaders(response.requestOptions.headers),
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
      response.data = ResponseBody(
        boundStream.map(
            (chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk)),
        responseBody.statusCode,
        headers: responseBody.headers,
        statusMessage: responseBody.statusMessage,
        isRedirect: responseBody.isRedirect,
        redirects: responseBody.redirects,
      );
      handler.next(response);
      return;
    }

    var contentLength = 0;
    final contentLengthHeader =
        response.headers.value(Headers.contentLengthHeader);
    if (contentLengthHeader != null) {
      contentLength = int.tryParse(contentLengthHeader) ?? 0;
    }
    if (contentLength <= 0) {
      final data = response.data;
      if (data is List<int>) {
        contentLength = data.length;
      } else if (data is String) {
        contentLength = data.length;
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
    final responseData = response.data;

    unawaited(
      guardCaptureAsync(() async {
        final resBytes = _toBytes(responseData, resContentType);
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
            requestHeaders: normalizeHeaders(err.requestOptions.headers),
          ),
        );
    err.requestOptions.extra.remove('interceptly_http_context');
    err.requestOptions.extra.remove('interceptly_req_bytes');

    final response = err.response;
    if (err.type == DioExceptionType.badResponse && response != null) {
      final resContentType = response.headers.value(Headers.contentTypeHeader);
      unawaited(
        guardCaptureAsync(() async {
          final resBytes = _toBytes(response.data, resContentType);
          await effectiveScope.complete(
            statusCode: response.statusCode ?? 0,
            headers: normalizeHeaders(response.headers.map),
            bodyBytes: resBytes,
            contentType: resContentType,
          );
        }),
      );
    } else {
      final resContentType = response?.headers.value(Headers.contentTypeHeader);
      final responseBodyBytes =
          response != null ? _toBytes(response.data, resContentType) : null;
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
