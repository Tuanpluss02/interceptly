import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:interceptly/interceptly.dart';

/// A Chopper interceptor that captures all requests and responses.
class InterceptlyChopperInterceptor
    implements Interceptor, HttpCaptureAdapter {
  /// Creates an interceptor backed by [collector].
  InterceptlyChopperInterceptor([
    HttpTrafficCollector? collector,
  ]) : collector = collector ?? DefaultHttpTrafficCollector();

  @override
  InspectorSession get session => InspectorSession.instance;

  @override
  final HttpTrafficCollector collector;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(
    Chain<BodyType> chain,
  ) async {
    final request = chain.request;

    final reqBody = guardCapture(() => _encodeBody(request.body));
    final reqContentType = headerValue(request.headers, 'content-type');

    HttpRequestContext? context;
    try {
      context = await collector.startRequest(
        method: request.method,
        uri: request.url,
        headers: request.headers,
        bodyBytes: reqBody,
        contentType: reqContentType,
      );
    } on SimulatedNetworkException {
      rethrow;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Interceptly] startRequest capture failed: $e\n$st');
      }
    }

    final Response<BodyType> response;
    try {
      response = await chain.proceed(request);
    } catch (e) {
      if (context != null) {
        collector.failRequest(
          context: context,
          error: e,
          errorType: e.runtimeType.toString(),
          errorMessage: e.toString(),
        );
      }
      rethrow;
    }

    final resBody = guardCapture(() => response.bodyBytes);
    final sent = response.base.request;
    final sentHeaders = sent?.headers ?? request.headers;
    final sentBody = sent is http.Request ? sent.bodyBytes : reqBody;

    final effectiveContext = context == null
        ? null
        : HttpRequestContext(
            id: context.id,
            method: sent?.method ?? context.method,
            uri: sent?.url ?? context.uri,
            startedAt: context.startedAt,
            requestHeaders: sentHeaders,
            requestBodyBytes: sentBody ?? context.requestBodyBytes,
            requestContentType:
                headerValue(sentHeaders, 'content-type') ??
                context.requestContentType,
          );

    if (effectiveContext != null) {
      await guardCaptureAsync(() async {
        await collector.completeResponse(
          context: effectiveContext,
          statusCode: response.statusCode,
          headers: response.base.headers,
          bodyBytes: resBody,
          responseContentType:
              headerValue(response.base.headers, 'content-type'),
        );
      });
    }

    return response;
  }

  static Uint8List? _encodeBody(Object? body) => encodeBodyBytes(body);
}
