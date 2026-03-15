import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/request_id.dart';
import '../../model/network_simulation.dart';
import '../../model/raw_capture.dart';
import '../../storage/inspector_session.dart';

/// A Dio interceptor that captures requests and responses for Interceptly.
class InterceptlyDioInterceptor extends Interceptor {
  /// Creates an interceptor backed by [session] or the shared singleton.
  InterceptlyDioInterceptor([InspectorSession? session])
      : session = session ?? InspectorSession.instance;

  /// Session that stores all captured events.
  final InspectorSession session;

  static const String _startedAtKey = 'interceptly_started_at';
  static const String _requestIdKey = 'interceptly_request_id';

  /// Captures a pending request and applies pre-request simulation.
  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final startedAt = DateTime.now();
    final id = RequestId.generate();

    options.extra[_startedAtKey] = startedAt;
    options.extra[_requestIdKey] = id;

    final reqBytes = _toBytes(options.data, options.contentType);
    session.recordPending(
      id: id,
      method: options.method,
      url: options.uri.toString(),
      timestamp: startedAt,
      requestHeaders: options.headers.map(
        (k, v) => MapEntry(k, v.toString()),
      ),
      requestBodyBytes: reqBytes,
      requestContentType: options.contentType,
    );

    try {
      await session.applyNetworkSimulationBeforeRequest(
        uploadBytes: reqBytes?.length ?? 0,
      );
    } on SimulatedNetworkException catch (e) {
      _record(
        options: options,
        errorType: 'SimulatedNetworkException',
        errorMessage: e.toString(),
      );
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
    final resContentType = response.headers.value(Headers.contentTypeHeader);
    final resBytes = _toBytes(response.data, resContentType);
    await session.applyNetworkSimulationAfterResponse(
      downloadBytes: resBytes?.length ?? 0,
    );

    _record(
      options: response.requestOptions,
      response: response,
    );
    handler.next(response);
  }

  /// Captures a Dio failure response or transport error.
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _record(
      options: err.requestOptions,
      response: err.response,
      errorType: err.type.name,
      errorMessage: err.message ?? err.error.toString(),
    );
    handler.next(err);
  }

  void _record({
    required RequestOptions options,
    Response<dynamic>? response,
    String? errorType,
    String? errorMessage,
  }) {
    final startedAt =
        options.extra[_startedAtKey] as DateTime? ?? DateTime.now();
    final id = options.extra[_requestIdKey] as String? ?? RequestId.generate();
    final durationMs = DateTime.now().difference(startedAt).inMilliseconds;

    final reqBytes = _toBytes(options.data, options.contentType);
    final resContentType = response?.headers.value(Headers.contentTypeHeader);
    final resBytes = _toBytes(response?.data, resContentType);

    final capture = RawCapture(
      id: id,
      method: options.method,
      url: options.uri.toString(),
      requestHeaders: options.headers.map(
        (k, v) => MapEntry(k, v.toString()),
      ),
      responseHeaders: response?.headers.map.map(
            (k, v) => MapEntry(k, v.join(', ')),
          ) ??
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

  /// Converts request/response data to raw bytes for the capture.
  ///
  /// - `String` → UTF-8 encoded
  /// - `Map` / `List` → JSON UTF-8
  /// - `FormData` → URL-encoded fields + file placeholders
  /// - `List<int>` / `Uint8List` → as-is
  /// - everything else → toString() UTF-8
  static Uint8List? _toBytes(Object? data, [String? contentType]) {
    if (data == null) return null;

    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);

    if (data is String) {
      return utf8.encode(data);
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
