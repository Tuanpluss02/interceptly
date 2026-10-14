import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:interceptly/adapter.dart';
import 'package:interceptly_chopper/interceptly_chopper.dart';

class _FakeChain<BodyType> implements Chain<BodyType> {
  _FakeChain(this.request, this.responseHandler);

  @override
  final Request request;
  final FutureOr<Response<BodyType>> Function(Request request) responseHandler;
  Request? proceededRequest;

  @override
  FutureOr<Response<BodyType>> proceed(Request request) {
    proceededRequest = request;
    return responseHandler(request);
  }
}

class _SpyHttpTrafficCollector implements HttpTrafficCollector {
  _SpyHttpTrafficCollector([InspectorSession? session])
      : session = session ?? InspectorSession.instance;

  final InspectorSession session;
  HttpRequestContext? nextContext;
  bool returnNullContext = false;
  bool throwSimulatedException = false;

  final List<Map<String, dynamic>> startRequestCalls = [];
  final List<Map<String, dynamic>> completeResponseCalls = [];
  final List<Map<String, dynamic>> failRequestCalls = [];

  @override
  int get maxBodyBytes => session.settings.maxBodyBytes;

  @override
  Duration delayForChunk(int chunkBytes) =>
      session.throughputDelayForChunk(chunkBytes);

  @override
  Future<HttpCaptureScope> begin({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    String? contentType,
    String? requestId,
  }) async {
    final context = await startRequest(
      method: method,
      uri: uri,
      headers: headers,
      bodyBytes: bodyBytes,
      contentType: contentType,
      requestId: requestId,
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
    startRequestCalls.add({
      'method': method,
      'uri': uri,
      'headers': headers,
      'bodyBytes': bodyBytes,
      'contentType': contentType,
      'requestId': requestId,
    });

    if (throwSimulatedException) {
      throw const SimulatedNetworkException('Pre-request simulation: offline');
    }

    if (returnNullContext) {
      return null;
    }

    final context = nextContext ??
        HttpRequestContext(
          id: requestId ?? 'spy-req-id',
          method: method,
          uri: uri,
          startedAt: DateTime.now(),
          requestHeaders: headers ?? const {},
          requestBodyBytes: bodyBytes,
          requestContentType: contentType,
        );
    return context;
  }

  @override
  Future<void> completeResponse({
    required HttpRequestContext context,
    required int statusCode,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    int? durationMs,
    String? responseContentType,
  }) async {
    completeResponseCalls.add({
      'context': context,
      'statusCode': statusCode,
      'headers': headers,
      'bodyBytes': bodyBytes,
      'durationMs': durationMs,
      'responseContentType': responseContentType,
    });
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
    int? durationMs,
  }) {
    failRequestCalls.add({
      'context': context,
      'error': error,
      'errorType': errorType,
      'errorMessage': errorMessage,
      'statusCode': statusCode,
      'responseHeaders': responseHeaders,
      'responseBodyBytes': responseBodyBytes,
      'durationMs': durationMs,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InspectorSession session;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('interceptly_chopper_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      },
    );
    await InspectorSession.resetForTesting();
    session = InspectorSession.instance;
    await session.initialize();
  });

  tearDown(() async {
    await session.dispose();
    await InspectorSession.resetForTesting();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('InterceptlyChopperInterceptor contracts and injection', () {
    test('uses DefaultHttpTrafficCollector by default', () {
      final interceptor = InterceptlyChopperInterceptor();
      expect(interceptor.collector, isA<DefaultHttpTrafficCollector>());
      final defaultCollector =
          interceptor.collector as DefaultHttpTrafficCollector;
      expect(defaultCollector.session, same(InspectorSession.instance));
    });

    test('constructs with custom HttpTrafficCollector', () {
      final spyCollector = _SpyHttpTrafficCollector();
      final interceptor = InterceptlyChopperInterceptor(spyCollector);
      expect(interceptor.collector, same(spyCollector));
    });
  });

  group('Lifecycle delegation to HttpTrafficCollector', () {
    test('delegates successful request/response to collector', () async {
      final spy = _SpyHttpTrafficCollector(session);
      final interceptor = InterceptlyChopperInterceptor(spy);

      final request = Request(
        'POST',
        Uri.parse('https://api.example.com/items'),
        Uri.parse('https://api.example.com'),
        body: '{"name":"book"}',
        headers: {'content-type': 'application/json', 'x-custom': 'val'},
      );

      final chain = _FakeChain<String>(
        request,
        (req) => Response(
          http.Response(
            '{"id":123}',
            200,
            headers: {'content-type': 'application/json', 'x-resp': 'ok'},
            request: http.Request('POST', req.url),
          ),
          '{"id":123}',
        ),
      );

      final response = await interceptor.intercept(chain);
      expect(response.statusCode, 200);

      // Verify collector.startRequest
      expect(spy.startRequestCalls.length, 1);
      final startCall = spy.startRequestCalls.first;
      expect(startCall['method'], 'POST');
      expect(startCall['uri'], Uri.parse('https://api.example.com/items'));
      expect(startCall['headers'], request.headers);
      expect(startCall['contentType'], 'application/json');
      expect(startCall['bodyBytes'], isNotNull);
      expect(
          utf8.decode(startCall['bodyBytes'] as Uint8List), '{"name":"book"}');

      // Verify collector.completeResponse
      expect(spy.completeResponseCalls.length, 1);
      final completeCall = spy.completeResponseCalls.first;
      expect(completeCall['statusCode'], 200);
      expect(completeCall['headers'],
          {'content-type': 'application/json', 'x-resp': 'ok'});
      expect(completeCall['responseContentType'], 'application/json');
      expect(utf8.decode(completeCall['bodyBytes'] as Uint8List), '{"id":123}');

      // Verify no failure calls
      expect(spy.failRequestCalls, isEmpty);
    });

    test(
        'delegates unsuccessful HTTP response (isSuccessful = false) to collector.completeResponse',
        () async {
      final spy = _SpyHttpTrafficCollector(session);
      final interceptor = InterceptlyChopperInterceptor(spy);

      final request = Request(
        'GET',
        Uri.parse('https://api.example.com/missing'),
        Uri.parse('https://api.example.com'),
      );

      final chain = _FakeChain<String>(
        request,
        (req) => Response(
          http.Response(
            '{"error":"not_found"}',
            404,
            headers: {'content-type': 'application/json'},
            request: http.Request('GET', req.url),
          ),
          '{"error":"not_found"}',
          error: 'Resource not found',
        ),
      );

      final response = await interceptor.intercept(chain);
      expect(response.statusCode, 404);
      expect(response.isSuccessful, isFalse);

      expect(spy.startRequestCalls.length, 1);
      expect(spy.failRequestCalls, isEmpty);

      expect(spy.completeResponseCalls.length, 1);
      final completeCall = spy.completeResponseCalls.first;
      expect(completeCall['statusCode'], 404);
      expect(completeCall['headers'], {'content-type': 'application/json'});
      expect(completeCall['bodyBytes'], isNotNull);
      expect(utf8.decode(completeCall['bodyBytes'] as Uint8List),
          '{"error":"not_found"}');
    });

    test(
        'delegates transport/client exception during proceed to collector.failRequest and rethrows',
        () async {
      final spy = _SpyHttpTrafficCollector(session);
      final interceptor = InterceptlyChopperInterceptor(spy);

      final request = Request(
        'GET',
        Uri.parse('https://api.example.com/crash'),
        Uri.parse('https://api.example.com'),
      );

      final chain = _FakeChain<String>(
        request,
        (_) => throw http.ClientException('Host unreachable'),
      );

      await expectLater(
        () => interceptor.intercept(chain),
        throwsA(isA<http.ClientException>()),
      );

      expect(spy.startRequestCalls.length, 1);
      expect(spy.completeResponseCalls, isEmpty);

      expect(spy.failRequestCalls.length, 1);
      final failCall = spy.failRequestCalls.first;
      expect(failCall['error'], isA<http.ClientException>());
      expect(failCall['errorType'], 'ClientException');
      expect(failCall['errorMessage'], contains('Host unreachable'));
    });

    test(
        'rethrows SimulatedNetworkException thrown from collector.startRequest without calling chain.proceed',
        () async {
      final spy = _SpyHttpTrafficCollector(session)
        ..throwSimulatedException = true;
      final interceptor = InterceptlyChopperInterceptor(spy);

      final request = Request(
        'GET',
        Uri.parse('https://api.example.com/blocked'),
        Uri.parse('https://api.example.com'),
      );

      bool proceedCalled = false;
      final chain = _FakeChain<String>(
        request,
        (_) {
          proceedCalled = true;
          return Response(http.Response('ok', 200), 'ok');
        },
      );

      await expectLater(
        () => interceptor.intercept(chain),
        throwsA(isA<SimulatedNetworkException>()),
      );

      expect(proceedCalled, isFalse);
      expect(spy.startRequestCalls.length, 1);
      expect(spy.completeResponseCalls, isEmpty);
    });

    test('handles collector.startRequest returning null gracefully', () async {
      final spy = _SpyHttpTrafficCollector(session)..returnNullContext = true;
      final interceptor = InterceptlyChopperInterceptor(spy);

      final request = Request(
        'GET',
        Uri.parse('https://api.example.com/disabled'),
        Uri.parse('https://api.example.com'),
      );

      final chain = _FakeChain<String>(
        request,
        (req) => Response(
          http.Response('ok', 200, request: http.Request('GET', req.url)),
          'ok',
        ),
      );

      final response = await interceptor.intercept(chain);
      expect(response.statusCode, 200);
      expect(chain.proceededRequest, isNotNull);
      expect(spy.startRequestCalls.length, 1);
      expect(spy.completeResponseCalls, isEmpty);
      expect(spy.failRequestCalls, isEmpty);
    });
  });

  group(
      'End-to-end capture with DefaultHttpTrafficCollector and InspectorSession',
      () {
    test(
      'InterceptlyChopperInterceptor does not alter outbound request.parameters',
      () async {
        final interceptor = InterceptlyChopperInterceptor();

        final originalParams = <String, dynamic>{
          'page': '1',
          'filter': 'active',
          'query': 'dart',
        };
        final request = Request(
          'GET',
          Uri.parse('https://api.example.com/items'),
          Uri.parse('https://api.example.com'),
          parameters: Map<String, dynamic>.from(originalParams),
        );

        final chain = _FakeChain<String>(
          request,
          (req) => Response(
            http.Response(
              '{"items":[]}',
              200,
              request: http.Request('GET', req.url),
            ),
            '{"items":[]}',
          ),
        );

        final response = await interceptor.intercept(chain);

        expect(chain.proceededRequest, isNotNull);
        expect(chain.proceededRequest!.parameters, equals(originalParams));
        expect(
          chain.proceededRequest!.parameters.containsKey(
            'interceptly_started_at',
          ),
          isFalse,
        );
        expect(
          chain.proceededRequest!.parameters.containsKey(
            'interceptly_request_id',
          ),
          isFalse,
        );

        expect(response.statusCode, 200);
        expect(response.body, '{"items":[]}');

        final end = DateTime.now().add(const Duration(seconds: 3));
        while (
            session.entries.isEmpty || session.entries.first.statusCode == 0) {
          if (DateTime.now().isAfter(end)) break;
          await Future.delayed(const Duration(milliseconds: 50));
        }

        expect(session.entries.length, 1);
        final entry = session.entries.first;
        expect(entry.url, contains('https://api.example.com/items'));
        expect(entry.url, isNot(contains('interceptly_started_at')));
        expect(entry.url, isNot(contains('interceptly_request_id')));
        expect(entry.method, 'GET');
        expect(entry.id, isNotEmpty);
        expect(entry.statusCode, 200);
        expect(entry.hasError, isFalse);
      },
    );

    test('preserves empty parameters without adding tracking keys', () async {
      final interceptor = InterceptlyChopperInterceptor();

      final request = Request(
        'POST',
        Uri.parse('https://api.example.com/login'),
        Uri.parse('https://api.example.com'),
        body: '{"user":"alice"}',
        headers: {'content-type': 'application/json'},
      );

      final chain = _FakeChain<String>(
        request,
        (req) => Response(
          http.Response(
            '{"token":"abc"}',
            201,
            request: http.Request('POST', req.url),
          ),
          '{"token":"abc"}',
        ),
      );

      final response = await interceptor.intercept(chain);

      expect(chain.proceededRequest!.parameters, isEmpty);
      expect(response.statusCode, 201);

      final end = DateTime.now().add(const Duration(seconds: 3));
      while (session.entries.isEmpty || session.entries.first.statusCode == 0) {
        if (DateTime.now().isAfter(end)) break;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      expect(session.entries.length, 1);
      final entry = session.entries.first;
      expect(entry.url, isNot(contains('interceptly_started_at')));
      expect(entry.url, isNot(contains('interceptly_request_id')));
    });

    test('captures transport exception when chain.proceed throws', () async {
      final interceptor = InterceptlyChopperInterceptor();

      final request = Request(
        'GET',
        Uri.parse('https://api.example.com/broken'),
        Uri.parse('https://api.example.com'),
        parameters: {'retry': 'false'},
      );

      final chain = _FakeChain<String>(
        request,
        (req) => throw http.ClientException('Connection failed'),
      );

      await expectLater(
        () => interceptor.intercept(chain),
        throwsA(isA<http.ClientException>()),
      );

      final end = DateTime.now().add(const Duration(seconds: 3));
      while (session.entries.isEmpty || !session.entries.first.hasError) {
        if (DateTime.now().isAfter(end)) break;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      expect(session.entries.length, 1);
      expect(chain.proceededRequest!.parameters, equals({'retry': 'false'}));
      final entry = session.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, 'ClientException');
    });

    test('captures HTTP error responses from server', () async {
      final interceptor = InterceptlyChopperInterceptor();

      final request = Request(
        'GET',
        Uri.parse('https://api.example.com/missing'),
        Uri.parse('https://api.example.com'),
      );

      final chain = _FakeChain<String>(
        request,
        (req) => Response(
          http.Response(
            '{"error":"not_found"}',
            404,
            request: http.Request('GET', req.url),
          ),
          '{"error":"not_found"}',
          error: 'Not Found',
        ),
      );

      final response = await interceptor.intercept(chain);

      expect(response.statusCode, 404);
      expect(response.isSuccessful, isFalse);
      expect(chain.proceededRequest!.parameters, isEmpty);

      final end = DateTime.now().add(const Duration(seconds: 3));
      while (session.entries.isEmpty || session.entries.first.statusCode == 0) {
        if (DateTime.now().isAfter(end)) break;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      expect(session.entries.length, 1);
      final entry = session.entries.first;
      expect(entry.statusCode, 404);
      expect(entry.hasError, isFalse);
      expect(entry.errorType, isNull);
    });

    test(
        'records SimulatedNetworkException when offline network simulation is active',
        () async {
      session.setNetworkSimulation(NetworkSimulationProfile.offlineProfile);
      final interceptor = InterceptlyChopperInterceptor();

      final request = Request(
        'GET',
        Uri.parse('https://api.example.com/offline'),
        Uri.parse('https://api.example.com'),
      );

      bool proceedCalled = false;
      final chain = _FakeChain<String>(
        request,
        (_) {
          proceedCalled = true;
          return Response(http.Response('ok', 200), 'ok');
        },
      );

      await expectLater(
        () => interceptor.intercept(chain),
        throwsA(isA<SimulatedNetworkException>()),
      );

      expect(proceedCalled, isFalse);

      final end = DateTime.now().add(const Duration(seconds: 3));
      while (session.entries.isEmpty || !session.entries.first.hasError) {
        if (DateTime.now().isAfter(end)) break;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      expect(session.entries.length, 1);
      final entry = session.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, 'SimulatedNetworkException');
    });
  });
}
