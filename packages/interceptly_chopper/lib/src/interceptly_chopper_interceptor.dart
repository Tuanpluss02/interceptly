import 'dart:async';
import 'dart:convert';

import 'package:chopper/chopper.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:interceptly/interceptly.dart';

/// A Chopper interceptor that captures all requests and responses.
class InterceptlyChopperInterceptor
    implements Interceptor, HttpCaptureAdapter {
  /// Creates an interceptor backed by [session] and [collector].
  InterceptlyChopperInterceptor([
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
        if (response.isSuccessful) {
          await collector.completeResponse(
            context: effectiveContext,
            statusCode: response.statusCode,
            headers: response.base.headers,
            bodyBytes: resBody,
            responseContentType:
                headerValue(response.base.headers, 'content-type'),
          );
        } else {
          await session.applyNetworkSimulationAfterResponse(
            downloadBytes: resBody?.length ?? 0,
          );
          collector.failRequest(
            context: effectiveContext,
            error: response.error ?? 'ChopperError',
            errorType: 'ChopperError',
            errorMessage: response.error?.toString(),
            statusCode: response.statusCode,
            responseHeaders: response.base.headers,
            responseBodyBytes: resBody,
          );
        }
      });
    }

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
