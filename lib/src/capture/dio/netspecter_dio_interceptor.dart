import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/request_id.dart';
import '../../model/raw_capture.dart';
import '../../storage/inspector_session.dart';

class NetSpecterDioInterceptor extends Interceptor {
  NetSpecterDioInterceptor([InspectorSession? session])
      : session = session ?? InspectorSession.instance;

  final InspectorSession session;

  static const String _startedAtKey = 'netspecter_started_at';
  static const String _requestIdKey = 'netspecter_request_id';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAtKey] = DateTime.now();
    options.extra[_requestIdKey] = RequestId.generate();
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _record(
      options: response.requestOptions,
      response: response,
    );
    handler.next(response);
  }

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
