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
    final reqBytes = await guardCaptureAsync<Uint8List?>(
      () => _toBytesAsync(options.data, options.contentType),
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
    final scope = (response.requestOptions.extra.remove(_scopeKey)
            as HttpCaptureScope?) ??
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
      final boundStream = scope.bindResponseStream(
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

    final resBytes = await guardCaptureAsync(
      () => _toBytesAsync(response.data, resContentType),
    );
    await scope.complete(
      statusCode: response.statusCode ?? 200,
      headers: normalizeHeaders(response.headers.map),
      bodyBytes: resBytes,
      contentType: resContentType,
    );

    handler.next(response);
  }

  /// Captures a Dio failure response or transport error.
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.error is SimulatedNetworkException) {
      handler.next(err);
      return;
    }

    final scope =
        (err.requestOptions.extra.remove(_scopeKey) as HttpCaptureScope?) ??
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
          final resBytes = await _toBytesAsync(response.data, resContentType);
          await scope.complete(
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

      scope.fail(
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

  /// Serializes arbitrary data to UTF-8 bytes in an isolate when appropriate.
  static Future<Uint8List?> _toBytesAsync(
    Object? data, [
    String? contentType,
  ]) async {
    if (data == null) return null;
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);

    if (data is String) {
      return _utf8Encode(data);
    }

    if (data is Map || data is List) {
      final isLarge = (data is List && data.length > 100) ||
          (data is Map && data.length > 100);
      if (isLarge) {
        return compute(_encodeJsonBytes, data);
      }
      return _toBytes(data, contentType);
    }

    return _toBytes(data, contentType);
  }

  static Uint8List _encodeJsonBytes(Object? data) {
    return encodeBodyBytes(data) ?? Uint8List(0);
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

/// Encodes [text] into UTF-8 bytes synchronously without isolate overhead.
Uint8List _utf8Encode(String text) => utf8.encode(text);
