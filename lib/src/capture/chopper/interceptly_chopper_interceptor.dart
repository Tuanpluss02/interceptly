import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chopper/chopper.dart';

import '../../session/request_id.dart';
import '../../model/network_simulation.dart';
import '../../model/raw_capture.dart';
import '../../session/inspector_session.dart';

/// A Chopper interceptor that captures all requests and responses.
class InterceptlyChopperInterceptor implements Interceptor {
  InterceptlyChopperInterceptor([InspectorSession? session])
      : session = session ?? InspectorSession.instance;

  final InspectorSession session;

  static const String _startedAtKey = 'interceptly_started_at';
  static const String _requestIdKey = 'interceptly_request_id';

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(
    Chain<BodyType> chain,
  ) async {
    final request = chain.request;
    final startedAt = DateTime.now();
    final requestId = RequestId.generate();

    final reqBody = _extractBody((request as dynamic).body);
    session.recordPending(
      id: requestId,
      method: request.method,
      url: request.url.toString(),
      timestamp: startedAt,
      requestHeaders: request.headers,
      requestBodyBytes: reqBody != null ? Uint8List.fromList(reqBody) : null,
      requestContentType: request.headers['content-type'],
    );

    try {
      await session.applyNetworkSimulationBeforeRequest(
        uploadBytes: reqBody?.length ?? 0,
      );
    } on SimulatedNetworkException catch (e) {
      final capture = RawCapture(
        id: requestId,
        method: request.method,
        url: request.url.toString(),
        requestHeaders: request.headers,
        responseHeaders: const {},
        statusCode: 0,
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
        timestamp: startedAt,
        requestBodyBytes: RawCapture.wrapBytes(
          reqBody != null ? Uint8List.fromList(reqBody) : null,
        ),
        requestContentType: request.headers['content-type'],
        errorType: 'SimulatedNetworkException',
        errorMessage: e.toString(),
      );
      session.record(capture);
      rethrow;
    }

    final enrichedRequest = request.copyWith(
      parameters: {
        ...request.parameters,
        _startedAtKey: startedAt.toIso8601String(),
        _requestIdKey: requestId,
      },
    );

    final response = await chain.proceed(enrichedRequest);

    final requestUri = response.base.request?.url;
    final recordedRequestId =
        requestUri?.queryParameters[_requestIdKey] ?? RequestId.generate();
    final startedAtStr = requestUri?.queryParameters[_startedAtKey];
    final recordedStartedAt = startedAtStr != null
        ? DateTime.tryParse(startedAtStr) ?? DateTime.now()
        : DateTime.now();

    String captureUrl = requestUri?.toString() ?? '';
    if (requestUri != null) {
      final cleanParams = Map<String, String>.from(requestUri.queryParameters)
        ..remove(_startedAtKey)
        ..remove(_requestIdKey);
      captureUrl = requestUri
          .replace(queryParameters: cleanParams.isEmpty ? null : cleanParams)
          .toString();
    }

    final durationMs =
        DateTime.now().difference(recordedStartedAt).inMilliseconds;

    final responseRequestBody = _extractBody(
        response.base.request?.method == 'POST' ||
                response.base.request?.method == 'PUT' ||
                response.base.request?.method == 'PATCH'
            ? (response.base.request as dynamic).body
            : null);

    final resBody = _extractBody(response.body);

    await session.applyNetworkSimulationAfterResponse(
      downloadBytes: resBody?.length ?? 0,
    );

    final capture = RawCapture(
      id: recordedRequestId,
      method: response.base.request?.method ?? 'UNKNOWN',
      url: captureUrl,
      requestHeaders: response.base.request?.headers ?? {},
      responseHeaders: response.base.headers,
      statusCode: response.statusCode,
      durationMs: durationMs,
      timestamp: recordedStartedAt,
      requestBodyBytes: RawCapture.wrapBytes(responseRequestBody != null
          ? Uint8List.fromList(responseRequestBody)
          : null),
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
