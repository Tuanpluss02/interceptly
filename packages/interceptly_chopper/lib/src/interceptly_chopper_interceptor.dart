import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chopper/chopper.dart';
import 'package:http/http.dart' as http;

import '../../session/request_id.dart';
import '../../model/network_simulation.dart';
import '../../model/raw_capture.dart';
import '../../session/inspector_session.dart';
import '../capture_guard.dart';

/// A Chopper interceptor that captures all requests and responses.
class InterceptlyChopperInterceptor implements Interceptor {
  InterceptlyChopperInterceptor([InspectorSession? session])
      : session = session ?? InspectorSession.instance;

  final InspectorSession session;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(
    Chain<BodyType> chain,
  ) async {
    final request = chain.request;
    final startedAt = DateTime.now();
    final requestId = RequestId.generate();

    final reqBody = guardCapture(() => _encodeBody(request.body));
    final reqContentType = headerValue(request.headers, 'content-type');

    guardCapture(
      () => session.recordPending(
        id: requestId,
        method: request.method,
        url: request.url.toString(),
        timestamp: startedAt,
        requestHeaders: request.headers,
        requestBodyBytes: reqBody,
        requestContentType: reqContentType,
      ),
    );

    void recordFailure(Object error, String errorType) {
      guardCapture(
        () => session.record(
          RawCapture(
            id: requestId,
            method: request.method,
            url: request.url.toString(),
            requestHeaders: request.headers,
            responseHeaders: const {},
            statusCode: 0,
            durationMs: DateTime.now().difference(startedAt).inMilliseconds,
            timestamp: startedAt,
            requestBodyBytes: RawCapture.wrapBytes(reqBody),
            requestContentType: reqContentType,
            errorType: errorType,
            errorMessage: error.toString(),
          ),
        ),
      );
    }

    try {
      await session.applyNetworkSimulationBeforeRequest(
        uploadBytes: reqBody?.length ?? 0,
      );
    } on SimulatedNetworkException catch (e) {
      recordFailure(e, 'SimulatedNetworkException');
      rethrow;
    }

    final Response<BodyType> response;
    try {
      response = await chain.proceed(request);
    } catch (e) {
      recordFailure(e, e.runtimeType.toString());
      rethrow;
    }

    final durationMs = DateTime.now().difference(startedAt).inMilliseconds;

    final resBody = guardCapture(() => response.bodyBytes);

    await session.applyNetworkSimulationAfterResponse(
      downloadBytes: resBody?.length ?? 0,
    );

    guardCapture(() {
      final sent = response.base.request;
      final sentHeaders = sent?.headers ?? request.headers;
      final sentBody = sent is http.Request ? sent.bodyBytes : reqBody;

      session.record(
        RawCapture(
          id: requestId,
          method: sent?.method ?? request.method,
          url: sent?.url.toString() ?? request.url.toString(),
          requestHeaders: sentHeaders,
          responseHeaders: response.base.headers,
          statusCode: response.statusCode,
          durationMs: durationMs,
          timestamp: startedAt,
          requestBodyBytes: RawCapture.wrapBytes(sentBody),
          responseBodyBytes: RawCapture.wrapBytes(resBody),
          requestContentType:
              headerValue(sentHeaders, 'content-type') ?? reqContentType,
          responseContentType:
              headerValue(response.base.headers, 'content-type'),
          errorType: response.isSuccessful ? null : 'ChopperError',
          errorMessage:
              response.isSuccessful ? null : response.error?.toString(),
        ),
      );
    });

    return response;
  }

  static Uint8List? _encodeBody(Object? body) {
    if (body == null) return null;
    if (body is Uint8List) return body;
    if (body is List<int>) return Uint8List.fromList(body);
    if (body is String) return utf8.encode(body);
    try {
      return utf8.encode(jsonEncode(body));
    } catch (_) {
      return utf8.encode(body.toString());
    }
  }
}
