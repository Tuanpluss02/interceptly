import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:http/http.dart' as http;
import 'package:interceptly/adapter.dart';

/// A client exception thrown when requests are aborted due to simulated offline profiles.
class InterceptlySimulatedChopperException extends http.ClientException
    implements SimulatedNetworkException {
  /// Creates a simulated client exception.
  InterceptlySimulatedChopperException(super.message, [super.uri]);
}

/// A Chopper interceptor that captures all requests and responses for Interceptly.
class InterceptlyChopperInterceptor implements Interceptor {
  /// Creates an interceptor backed by [collector].
  InterceptlyChopperInterceptor([
    HttpTrafficCollector? collector,
  ]) : collector = collector ?? HttpTrafficCollector.instance;

  /// The traffic collector coordinating capture.
  final HttpTrafficCollector collector;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(
    Chain<BodyType> chain,
  ) async {
    final request = chain.request;
    if (!collector.shouldCapture(request.url)) {
      return chain.proceed(request);
    }
    final reqBody = encodeBodyBytes(request.body);
    final reqContentType = headerValue(request.headers, 'content-type');

    final HttpCaptureScope scope;
    try {
      scope = await collector.begin(
        method: request.method,
        uri: request.url,
        headers: request.headers,
        bodyBytes: reqBody,
        contentType: reqContentType,
      );
    } on SimulatedNetworkException catch (e) {
      throw InterceptlySimulatedChopperException(e.message, request.url);
    }

    final Response<BodyType> response;
    try {
      response = await chain.proceed(request);
    } catch (e, st) {
      scope.fail(e, stackTrace: st);
      rethrow;
    }

    final resBody = response.bodyBytes;
    final sent = response.base.request;
    final sentHeaders = sent?.headers ?? request.headers;
    final sentBody = sent is http.Request ? sent.bodyBytes : reqBody;

    scope.amendRequest(
      method: sent?.method,
      uri: sent?.url,
      headers: sentHeaders,
      bodyBytes: sentBody,
      contentType: headerValue(sentHeaders, 'content-type'),
    );

    await scope.complete(
      statusCode: response.statusCode,
      headers: response.base.headers,
      bodyBytes: resBody,
      contentType: headerValue(response.base.headers, 'content-type'),
    );

    return response;
  }
}
