import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:interceptly/interceptly.dart';

/// A Dio interceptor that captures requests and responses for Interceptly.
class InterceptlyDioInterceptor extends Interceptor
    implements HttpCaptureAdapter {
  /// Creates an interceptor backed by [session] and [collector].
  InterceptlyDioInterceptor([
    InspectorSession? session,
    HttpTrafficCollector? collector,
  ])  : session = session ??
            (collector is DefaultHttpTrafficCollector
                ? collector.session
                : InspectorSession.instance),
        collector = collector ??
            DefaultHttpTrafficCollector(
              session ?? InspectorSession.instance,
            );

  @override
  final InspectorSession session;

  @override
  final HttpTrafficCollector collector;

  static const String _contextKey = 'interceptly_http_context';
  static const String _reqBytesKey = 'interceptly_req_bytes';

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
      final context = await collector.startRequest(
        method: options.method,
        uri: options.uri,
        headers: _mapHeaders(options.headers),
        bodyBytes: reqBytes,
        contentType: options.contentType,
      );
      if (context != null) {
        options.extra[_contextKey] = context;
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
    final extraContext =
        response.requestOptions.extra[_contextKey] as HttpRequestContext?;
    final context = extraContext ??
        (session.isEnabled
            ? HttpRequestContext(
                id: RequestId.generate(),
                method: response.requestOptions.method,
                uri: response.requestOptions.uri,
                startedAt: DateTime.now(),
                requestHeaders: _mapHeaders(response.requestOptions.headers),
              )
            : null);

    if (context != null) {
      final resContentType =
          response.headers.value(Headers.contentTypeHeader);
      final resBytes = await guardCaptureAsync(
        () => _toBytesAsync(response.data, resContentType),
      );
      try {
        await collector.completeResponse(
          context: context,
          statusCode: response.statusCode ?? 200,
          headers: _mapHeaders(response.headers.map),
          bodyBytes: resBytes,
          responseContentType: resContentType,
        );
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[Interceptly] completeResponse capture failed: $e\n$st');
        }
      } finally {
        response.requestOptions.extra.remove(_contextKey);
        response.requestOptions.extra.remove(_reqBytesKey);
      }
    }

    handler.next(response);
  }

  /// Captures a Dio failure response or transport error.
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.error is SimulatedNetworkException) {
      handler.next(err);
      return;
    }

    try {
      final extraContext =
          err.requestOptions.extra[_contextKey] as HttpRequestContext?;
      final context = extraContext ??
          HttpRequestContext(
            id: RequestId.generate(),
            method: err.requestOptions.method,
            uri: err.requestOptions.uri,
            startedAt: DateTime.now(),
            requestHeaders: _mapHeaders(err.requestOptions.headers),
          );

      final response = err.response;
      if (err.type == DioExceptionType.badResponse && response != null) {
        final resContentType =
            response.headers.value(Headers.contentTypeHeader);
        final resBytes = await guardCaptureAsync(
          () => _toBytesAsync(response.data, resContentType),
        );
        await collector.completeResponse(
          context: context,
          statusCode: response.statusCode ?? 0,
          headers: _mapHeaders(response.headers.map),
          bodyBytes: resBytes,
          responseContentType: resContentType,
        );
      } else {
        guardCapture(() {
          final resContentType =
              response?.headers.value(Headers.contentTypeHeader);
          final responseBodyBytes =
              response != null ? _toBytes(response.data, resContentType) : null;
          final responseHeaders =
              response != null ? _mapHeaders(response.headers.map) : null;

          collector.failRequest(
            context: context,
            error: err.error ?? err,
            errorType: err.type.name,
            errorMessage: err.message ?? err.error?.toString(),
            statusCode: response?.statusCode,
            responseHeaders: responseHeaders,
            responseBodyBytes: responseBodyBytes,
          );
        });
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Interceptly] onError capture failed: $e\n$st');
      }
    } finally {
      err.requestOptions.extra.remove(_contextKey);
      err.requestOptions.extra.remove(_reqBytesKey);
      handler.next(err);
    }
  }

  static Map<String, String> _mapHeaders(Map<String, dynamic> headers) {
    return normalizeHeaders(headers);
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

  /// Converts request/response data to raw bytes for the capture synchronously.
  static Uint8List? _toBytes(Object? data, [String? contentType]) {
    if (data == null) return null;

    if (data is ResponseBody) {
      return utf8.encode('[streamed response]');
    }

    if (data is FormData) {
      final parts = <String>[];
      if (data.fields.isNotEmpty) {
        parts.add(data.fields.map((e) => '${e.key}=${e.value}').join('&'));
      }
      for (final entry in data.files) {
        final meta = entry.value;
        final type = meta.contentType?.mimeType ?? 'application/octet-stream';
        parts.add('[file] ${entry.key}: ${meta.filename ?? 'blob'} ($type)');
      }
      return utf8.encode(parts.join('\n'));
    }

    return encodeBodyBytes(data);
  }
}

/// Encodes [text] into UTF-8 bytes synchronously without isolate overhead.
Uint8List _utf8Encode(String text) => utf8.encode(text);
