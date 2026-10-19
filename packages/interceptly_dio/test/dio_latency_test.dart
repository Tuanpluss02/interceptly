import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/adapter.dart';
import 'package:interceptly_dio/interceptly_dio.dart';

class _BlockingCollector implements HttpTrafficCollector {
  final Completer<void> completeCompleter = Completer<void>();
  bool completeResponseCalled = false;
  final List<Map<String, dynamic>> completedCalls = [];

  Duration simulatedThroughputDelay = Duration.zero;

  @override
  int get maxBodyBytes => 1024 * 1024;

  @override
  Duration delayForChunk(int chunkBytes) => simulatedThroughputDelay;

  @override
  bool shouldCapture(Uri? uri) => true;

  @override
  Future<HttpCaptureScope> begin({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    String? contentType,
    String? requestId,
  }) async {
    final context = HttpRequestContext(
      id: requestId ?? 'test-req',
      method: method,
      uri: uri,
      startedAt: DateTime.now(),
      requestHeaders: headers ?? const {},
      requestBodyBytes: bodyBytes,
      requestContentType: contentType,
    );
    return HttpCaptureScope(collector: this, context: context);
  }

  @override
  Future<HttpRequestContext?> startRequest({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    String? contentType,
    String? requestId,
  }) async {
    return HttpRequestContext(
      id: requestId ?? 'test-req',
      method: method,
      uri: uri,
      startedAt: DateTime.now(),
      requestHeaders: headers ?? const {},
      requestBodyBytes: bodyBytes,
      requestContentType: contentType,
    );
  }

  @override
  Future<void> completeResponse({
    required HttpRequestContext context,
    required int statusCode,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    int? responseSizeBytes,
    int? durationMs,
    String? responseContentType,
    bool? responseTruncatedAtStorage,
  }) async {
    completeResponseCalled = true;
    completedCalls.add({
      'context': context,
      'statusCode': statusCode,
      'headers': headers,
      'bodyBytes': bodyBytes,
    });
    await completeCompleter.future;
  }

  @override
  void failRequest({
    required HttpRequestContext context,
    required Object error,
    String? errorType,
    String? errorMessage,
    int? statusCode,
    Map<String, String>? responseHeaders,
    Uint8List? responseBodyBytes,
    int? responseSizeBytes,
    int? durationMs,
    bool? responseTruncatedAtStorage,
  }) {}
}

class _TrackingResponseHandler extends ResponseInterceptorHandler {
  bool nextCalled = false;
  Response<dynamic>? responseReceived;

  @override
  void next(Response<dynamic> response) {
    nextCalled = true;
    responseReceived = response;
    super.next(response);
  }
}

class _TrackingRequestHandler extends RequestInterceptorHandler {
  bool nextCalled = false;
  RequestOptions? optionsReceived;

  @override
  void next(RequestOptions requestOptions) {
    nextCalled = true;
    optionsReceived = requestOptions;
    super.next(requestOptions);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dio critical path decoupling and latency', () {
    test(
        'onResponse calls handler.next immediately without blocking on completeResponse',
        () async {
      final collector = _BlockingCollector();
      final interceptor = InterceptlyDioInterceptor(collector);
      final handler = _TrackingResponseHandler();

      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: 'https://api.example.com/items'),
        statusCode: 200,
        data: {'key': 'value'},
      );

      final future = interceptor.onResponse(response, handler);

      // In the decoupled design, handler.next must be called immediately.
      // With the old blocking design, handler.next is only called AFTER
      // collector.completeResponse finishes (which is blocked by completeCompleter).
      expect(
        handler.nextCalled,
        isTrue,
        reason: 'handler.next must be called before completeResponse finishes',
      );

      // Release the completer so background capture finishes
      collector.completeCompleter.complete();
      await future;
      expect(collector.completeResponseCalled, isTrue);
    });

    test(
        'onResponse serializes large body in background and captures accurately',
        () async {
      final collector = _BlockingCollector();
      collector.completeCompleter.complete();
      final interceptor = InterceptlyDioInterceptor(collector);
      final handler = _TrackingResponseHandler();

      final largePayload =
          List.generate(200, (i) => {'index': i, 'name': 'item_$i'});
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: 'https://api.example.com/large'),
        statusCode: 200,
        data: largePayload,
      );

      await interceptor.onResponse(response, handler);

      expect(handler.nextCalled, isTrue);
      // Wait for background serialization and capture to finish
      final end = DateTime.now().add(const Duration(seconds: 2));
      while (collector.completedCalls.isEmpty && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(collector.completedCalls.isNotEmpty, isTrue);
      final call = collector.completedCalls.first;
      expect(call['bodyBytes'], isNotNull);
      final decoded = jsonDecode(utf8.decode(call['bodyBytes'] as Uint8List));
      expect(decoded, isA<List>());
      expect((decoded as List).length, equals(200));
    });

    test(
        'onResponse awaits throughput simulation delay if delay > Duration.zero before handler.next',
        () async {
      final collector = _BlockingCollector();
      collector.simulatedThroughputDelay = const Duration(milliseconds: 60);
      collector.completeCompleter.complete();
      final interceptor = InterceptlyDioInterceptor(collector);
      final handler = _TrackingResponseHandler();

      final response = Response<dynamic>(
        requestOptions:
            RequestOptions(path: 'https://api.example.com/throttled'),
        statusCode: 200,
        headers: Headers.fromMap({
          Headers.contentLengthHeader: ['2048'],
        }),
        data: 'simulated response',
      );

      final stopwatch = Stopwatch()..start();
      await interceptor.onResponse(response, handler);
      stopwatch.stop();

      expect(handler.nextCalled, isTrue);
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(45));
    });

    test(
        'onRequest processes large request data directly without isolate spawning',
        () async {
      final collector = _BlockingCollector();
      final interceptor = InterceptlyDioInterceptor(collector);
      final handler = _TrackingRequestHandler();

      final largePayload = List.generate(200, (i) => {'index': i});
      final options = RequestOptions(
        path: 'https://api.example.com/upload',
        method: 'POST',
        data: largePayload,
        headers: {'content-type': 'application/json'},
      );

      await interceptor.onRequest(options, handler);

      expect(handler.nextCalled, isTrue);
      expect(handler.optionsReceived, same(options));
    });
  });
}
