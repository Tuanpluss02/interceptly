import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:chopper/chopper.dart';
import '../../core/request_id.dart';
import '../../model/raw_capture.dart';
import '../../storage/inspector_session.dart';

/// A Chopper interceptor that captures all requests and responses.
class NetSpecterChopperInterceptor
    implements RequestInterceptor, ResponseInterceptor {
  NetSpecterChopperInterceptor([InspectorSession? session])
      : session = session ?? InspectorSession.instance;

  final InspectorSession session;

  static const String _startedAtKey = 'netspecter_started_at';
  static const String _requestIdKey = 'netspecter_request_id';

  @override
  FutureOr<Request> onRequest(Request request) {
    return request.copyWith(
      parameters: {
        ...request.parameters,
        _startedAtKey: DateTime.now().toIso8601String(),
        _requestIdKey: RequestId.generate(),
      },
    );
  }

  @override
  FutureOr<Response> onResponse(Response response) {
    final requestId =
        response.base.request?.url.queryParameters[_requestIdKey] ??
            RequestId.generate();
    final startedAtStr =
        response.base.request?.url.queryParameters[_startedAtKey];
    final startedAt = startedAtStr != null
        ? DateTime.tryParse(startedAtStr) ?? DateTime.now()
        : DateTime.now();

    final durationMs = DateTime.now().difference(startedAt).inMilliseconds;

    final reqBody = _extractBody(response.base.request?.method == 'POST' ||
            response.base.request?.method == 'PUT' ||
            response.base.request?.method == 'PATCH'
        ? (response.base.request as dynamic).body
        : null);

    final resBody = _extractBody(response.body);

    final capture = RawCapture(
      id: requestId,
      method: response.base.request?.method ?? 'UNKNOWN',
      url: response.base.request?.url.toString() ?? '',
      requestHeaders: response.base.request?.headers ?? {},
      responseHeaders: response.base.headers,
      statusCode: response.statusCode,
      durationMs: durationMs,
      timestamp: startedAt,
      requestBodyBytes: RawCapture.wrapBytes(
          reqBody != null ? Uint8List.fromList(reqBody) : null),
      responseBodyBytes: RawCapture.wrapBytes(
          resBody != null ? Uint8List.fromList(resBody) : null),
      requestContentType: response.base.request?.headers['content-type'],
      responseContentType: response.base.headers['content-type'],
      errorType: response.isSuccessful ? null : 'ChopperError',
      errorMessage: response.isSuccessful ? null : response.error?.toString(),
    );

    session.record(capture);

    return response;
  }

  List<int>? _extractBody(dynamic body) {
    if (body == null) return null;
    if (body is List<int>) return body;
    if (body is String) return utf8.encode(body);
    try {
      return utf8.encode(jsonEncode(body));
    } catch (_) {
      return utf8.encode(body.toString());
    }
  }
}
