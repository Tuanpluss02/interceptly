import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../session/request_id.dart';
import '../../model/network_simulation.dart';
import '../../model/raw_capture.dart';
import '../../session/inspector_session.dart';
import '../capture_guard.dart';

/// A Dio interceptor that captures requests and responses for Interceptly.
class InterceptlyDioInterceptor extends Interceptor {
  /// Creates an interceptor backed by [session] or the shared singleton.
  InterceptlyDioInterceptor([InspectorSession? session])
      : session = session ?? InspectorSession.instance;

  /// Session that stores all captured events.
  final InspectorSession session;

  static const String _startedAtKey = 'interceptly_started_at';
  static const String _requestIdKey = 'interceptly_request_id';
  static const String _reqBytesKey = 'interceptly_req_bytes';

  /// Captures a pending request and applies pre-request simulation.
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final startedAt = DateTime.now();
    final id = RequestId.generate();

    options.extra[_startedAtKey] = startedAt;
    options.extra[_requestIdKey] = id;

    Uint8List? reqBytes;
    if (session.isEnabled) {
      reqBytes = await guardCaptureAsync<Uint8List?>(
          () => _toBytesAsync(options.data, options.contentType));
      options.extra[_reqBytesKey] = reqBytes;

      guardCapture(() {
        session.recordPending(
          id: id,
          method: options.method,
          url: options.uri.toString(),
          timestamp: startedAt,
          requestHeaders: _mapHeaders(options.headers),
          requestBodyBytes: reqBytes,
          requestContentType: options.contentType,
        );
      });
    }

    try {
      await session.applyNetworkSimulationBeforeRequest(
        uploadBytes: reqBytes?.length ?? 0,
      );
    } on SimulatedNetworkException catch (e) {
      guardCapture(() {
        _record(
          options: options,
          errorType: 'SimulatedNetworkException',
          errorMessage: e.toString(),
        );
      });
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: e,
          message: e.toString(),
        ),
      );
      return;
    }

    handler.next(options);
  }

  /// Captures a successful response and applies post-response simulation.
  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    await guardCaptureAsync(() async {
      final resContentType = response.headers.value(Headers.contentTypeHeader);
      final resBytes = await _toBytesAsync(response.data, resContentType);
      await session.applyNetworkSimulationAfterResponse(
        downloadBytes: resBytes?.length ?? 0,
      );

      await _recordAsync(
        options: response.requestOptions,
        response: response,
        resBytes: resBytes,
      );
    });

    handler.next(response);
  }

  /// Captures a Dio failure response or transport error.
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    guardCapture(() {
      _record(
        options: err.requestOptions,
        response: err.response,
        errorType: err.type.name,
        errorMessage: err.message ?? err.error?.toString(),
      );
    });

    handler.next(err);
  }

  Future<void> _recordAsync({
    required RequestOptions options,
    Response<dynamic>? response,
    Uint8List? resBytes,
    String? errorType,
    String? errorMessage,
  }) async {
    if (!session.isEnabled) return;

    final startedAt =
        options.extra[_startedAtKey] as DateTime? ?? DateTime.now();
    final id = options.extra[_requestIdKey] as String? ?? RequestId.generate();
    final durationMs = DateTime.now().difference(startedAt).inMilliseconds;

    final reqBytes = options.extra[_reqBytesKey] as Uint8List? ??
        await _toBytesAsync(options.data, options.contentType);
    final resContentType = response?.headers.value(Headers.contentTypeHeader);
    final finalResBytes = resBytes ??
        await _toBytesAsync(response?.data, resContentType);

    final capture = RawCapture(
      id: id,
      method: options.method,
      url: options.uri.toString(),
      requestHeaders: _mapHeaders(options.headers),
      responseHeaders:
          response?.headers.map.map((k, v) => MapEntry(k, v.join(', '))) ??
              const {},
      statusCode: response?.statusCode ?? 0,
      durationMs: durationMs,
      timestamp: startedAt,
      requestBodyBytes: RawCapture.wrapBytes(reqBytes),
      responseBodyBytes: RawCapture.wrapBytes(finalResBytes),
      requestContentType: options.contentType,
      responseContentType: resContentType,
      errorType: errorType,
      errorMessage: errorMessage,
    );

    session.record(capture);
  }

  void _record({
    required RequestOptions options,
    Response<dynamic>? response,
    String? errorType,
    String? errorMessage,
  }) {
    if (!session.isEnabled) return;

    final startedAt =
        options.extra[_startedAtKey] as DateTime? ?? DateTime.now();
    final id = options.extra[_requestIdKey] as String? ?? RequestId.generate();
    final durationMs = DateTime.now().difference(startedAt).inMilliseconds;

    final reqBytes = options.extra[_reqBytesKey] as Uint8List? ??
        _toBytes(options.data, options.contentType);
    final resContentType = response?.headers.value(Headers.contentTypeHeader);
    final resBytes = _toBytes(response?.data, resContentType);

    final capture = RawCapture(
      id: id,
      method: options.method,
      url: options.uri.toString(),
      requestHeaders: _mapHeaders(options.headers),
      responseHeaders:
          response?.headers.map.map((k, v) => MapEntry(k, v.join(', '))) ??
              const {},
      statusCode: response?.statusCode ?? 0,
      durationMs: durationMs,
      timestamp: startedAt,
      requestBodyBytes: RawCapture.wrapBytes(reqBytes),
      responseBodyBytes: RawCapture.wrapBytes(resBytes),
      requestContentType: options.contentType,
      responseContentType: resContentType,
      errorType: errorType,
      errorMessage: errorMessage,
    );

    session.record(capture);
  }

  static Map<String, String> _mapHeaders(Map<String, dynamic> headers) {
    return headers.map((k, v) {
      if (v is Iterable) {
        return MapEntry(k, v.join(', '));
      }
      return MapEntry(k, v.toString());
    });
  }

  /// Serializes arbitrary data to UTF-8 bytes in an isolate when appropriate.
  static Future<Uint8List?> _toBytesAsync(Object? data, [String? contentType]) async {
    if (data == null) return null;
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);

    if (data is String) {
      if (data.length > 50 * 1024) {
        return compute(utf8.encode, data);
      }
      return utf8.encode(data);
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
    try {
      return utf8.encode(jsonEncode(data));
    } catch (_) {
      return utf8.encode(data.toString());
    }
  }

  /// Converts request/response data to raw bytes for the capture synchronously.
  static Uint8List? _toBytes(Object? data, [String? contentType]) {
    if (data == null) return null;

    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);

    if (data is String) {
      return utf8.encode(data);
    }

    if (data is ResponseBody) {
      return utf8.encode('[streamed response]');
    }

    if (data is Map || data is List) {
      try {
        return utf8.encode(jsonEncode(data));
      } catch (_) {
        return utf8.encode(data.toString());
      }
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

    return utf8.encode(data.toString());
  }
}
