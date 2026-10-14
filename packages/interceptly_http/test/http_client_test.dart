import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_http/interceptly_http.dart';

class _StreamingMockClient extends http.BaseClient {
  _StreamingMockClient(this.streamController);

  final StreamController<List<int>> streamController;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      streamController.stream,
      200,
      request: request,
    );
  }
}

class _FailingMockClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw http.ClientException('Simulated network failure');
  }
}

class _FixedMockClient extends http.BaseClient {
  _FixedMockClient({
    this.statusCode = 200,
    this.responseBody = '{"ok":true}',
    this.headers = const {'content-type': 'application/json'},
  });

  final int statusCode;
  final String responseBody;
  final Map<String, String> headers;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = utf8.encode(responseBody);
    return http.StreamedResponse(
      Stream.value(bytes),
      statusCode,
      headers: headers,
      request: request,
    );
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

Future<void> _waitFor(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 4));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HttpCaptureAdapter Contract & Constructors', () {
    test('implements HttpCaptureAdapter and provides default collector and session', () {
      final inner = _FixedMockClient();
      final client = InterceptlyHttpClient(inner);

      expect(client, isA<HttpCaptureAdapter>());
      expect(client.session, same(InspectorSession.instance));
      expect(client.collector, isA<DefaultHttpTrafficCollector>());
      expect(
        (client.collector as DefaultHttpTrafficCollector).session,
        same(InspectorSession.instance),
      );
    });

    test('constructor accepts custom session and wires into DefaultHttpTrafficCollector', () {
      final inner = _FixedMockClient();
      final customSession = InspectorSession();
      final client = InterceptlyHttpClient(inner, customSession);

      expect(client.session, same(customSession));
      expect(client.collector, isA<DefaultHttpTrafficCollector>());
      expect(
        (client.collector as DefaultHttpTrafficCollector).session,
        same(customSession),
      );
    });

    test('constructor accepts DefaultHttpTrafficCollector and derives session', () {
      final inner = _FixedMockClient();
      final customSession = InspectorSession();
      final collector = DefaultHttpTrafficCollector(customSession);
      final client = InterceptlyHttpClient(inner, null, collector);

      expect(client.collector, same(collector));
      expect(client.session, same(customSession));
    });

    test('constructor accepts custom collector and falls back to instance session', () {
      final inner = _FixedMockClient();
      final spy = _SpyHttpTrafficCollector();
      final client = InterceptlyHttpClient(inner, null, spy);

      expect(client.collector, same(spy));
      expect(client.session, same(InspectorSession.instance));
    });

    test('wrap factory creates InterceptlyHttpClient with provided session and collector', () {
      final inner = _FixedMockClient();
      final spy = _SpyHttpTrafficCollector();
      final client = InterceptlyHttpClient.wrap(inner, null, spy);

      expect(client, isA<InterceptlyHttpClient>());
      expect(client, isA<HttpCaptureAdapter>());
      expect(client.collector, same(spy));
    });
  });

  group('Collector Delegation', () {
    test('delegates request and successful response to collector', () async {
      final spy = _SpyHttpTrafficCollector();
      final inner = _FixedMockClient(
        statusCode: 201,
        responseBody: '{"created":true}',
        headers: {
          'content-type': 'application/json',
          'x-custom-res': 'header-val',
        },
      );
      final client = InterceptlyHttpClient(inner, null, spy);

      final response = await client.post(
        Uri.parse('https://api.example.com/items'),
        headers: {
          'content-type': 'text/plain; charset=utf-8',
          'authorization': 'Bearer token123',
        },
        body: 'hello payload',
      );

      expect(response.statusCode, equals(201));

      expect(spy.startRequestCalls.length, equals(1));
      final startCall = spy.startRequestCalls.first;
      expect(startCall['method'], equals('POST'));
      expect(startCall['uri'], equals(Uri.parse('https://api.example.com/items')));
      expect((startCall['headers'] as Map<String, String>)['authorization'], equals('Bearer token123'));
      expect(startCall['contentType'], equals('text/plain; charset=utf-8'));
      expect(utf8.decode(startCall['bodyBytes'] as Uint8List), equals('hello payload'));

      expect(spy.completeResponseCalls.length, equals(1));
      final completeCall = spy.completeResponseCalls.first;
      expect(completeCall['statusCode'], equals(201));
      expect(completeCall['context'], isA<HttpRequestContext>());
      expect((completeCall['headers'] as Map<String, String>)['x-custom-res'], equals('header-val'));
      expect(completeCall['responseContentType'], equals('application/json'));
      expect(utf8.decode(completeCall['bodyBytes'] as Uint8List), equals('{"created":true}'));
    });

    test('delegates inner client failure to collector.failRequest', () async {
      final spy = _SpyHttpTrafficCollector();
      final inner = _FailingMockClient();
      final client = InterceptlyHttpClient(inner, null, spy);

      await expectLater(
        () => client.get(Uri.parse('https://api.example.com/failing')),
        throwsA(isA<http.ClientException>()),
      );

      expect(spy.failRequestCalls.length, equals(1));
      final failCall = spy.failRequestCalls.first;
      expect(failCall['context'], isA<HttpRequestContext>());
      expect(failCall['error'], isA<http.ClientException>());
      expect(failCall['errorType'], contains('ClientException'));
      expect(failCall['errorMessage'], contains('Simulated network failure'));
    });

    test('delegates stream error to collector.failRequest', () async {
      final spy = _SpyHttpTrafficCollector();
      final streamCtrl = StreamController<List<int>>();
      final inner = _StreamingMockClient(streamCtrl);
      final client = InterceptlyHttpClient(inner, null, spy);

      final response = await client.send(
        http.Request('GET', Uri.parse('https://api.example.com/stream-err')),
      );

      final completer = Completer<void>();
      response.stream.listen(
        (_) {},
        onError: (_) {
          if (!completer.isCompleted) completer.complete();
        },
      );

      streamCtrl.addError(Exception('stream broken mid-flight'));
      await streamCtrl.close();
      await completer.future;

      expect(spy.failRequestCalls.length, equals(1));
      final failCall = spy.failRequestCalls.first;
      expect(failCall['context'], isA<HttpRequestContext>());
      expect(failCall['errorType'], contains('Exception'));
      expect(failCall['errorMessage'], contains('stream broken mid-flight'));
      expect(failCall['statusCode'], equals(200));
    });

    test('delegates stream cancellation to collector.failRequest', () async {
      final spy = _SpyHttpTrafficCollector();
      final streamCtrl = StreamController<List<int>>();
      final inner = _StreamingMockClient(streamCtrl);
      final client = InterceptlyHttpClient(inner, null, spy);

      final response = await client.send(
        http.Request('GET', Uri.parse('https://api.example.com/stream-cancel')),
      );

      streamCtrl.add([1, 2, 3]);
      final sub = response.stream.listen((_) {});
      await sub.cancel();
      await streamCtrl.close();

      expect(spy.failRequestCalls.length, equals(1));
      final failCall = spy.failRequestCalls.first;
      expect(failCall['context'], isA<HttpRequestContext>());
      expect(failCall['errorType'], equals('CancellationException'));
      expect(failCall['errorMessage'], equals('Stream subscription was canceled by client.'));
      expect(failCall['statusCode'], equals(200));
    });

    test('rethrows SimulatedNetworkException when startRequest throws SimulatedNetworkException', () async {
      final spy = _SpyHttpTrafficCollector()..throwSimulatedException = true;
      final inner = _FixedMockClient();
      final client = InterceptlyHttpClient(inner, null, spy);

      await expectLater(
        () => client.get(Uri.parse('https://api.example.com/simulated')),
        throwsA(isA<SimulatedNetworkException>()),
      );

      expect(spy.startRequestCalls.length, equals(1));
      expect(spy.completeResponseCalls, isEmpty);
    });

    test('proceeds normally without recording when collector returns null context', () async {
      final spy = _SpyHttpTrafficCollector()..returnNullContext = true;
      final inner = _FixedMockClient(responseBody: 'test-payload');
      final client = InterceptlyHttpClient(inner, null, spy);

      final response = await client.get(Uri.parse('https://api.example.com/null-context'));

      expect(response.statusCode, equals(200));
      expect(response.body, equals('test-payload'));
      expect(spy.startRequestCalls.length, equals(1));
      expect(spy.completeResponseCalls, isEmpty);
      expect(spy.failRequestCalls, isEmpty);
    });
  });

  group('Integration with InspectorSession and Network Simulation', () {
    late Directory tempDir;
    late InspectorSession session;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('interceptly_http_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (call.method == 'getTemporaryDirectory') return tempDir.path;
          return null;
        },
      );
      session = InspectorSession();
      await session.initialize();
    });

    tearDown(() async {
      session.dispose();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test(
      'InterceptlyHttpClient records canceled streams promptly upon subscription cancellation',
      () async {
        final streamCtrl = StreamController<List<int>>();
        final innerClient = _StreamingMockClient(streamCtrl);
        final client = InterceptlyHttpClient(innerClient, session);

        final response = await client.send(
          http.Request('GET', Uri.parse('https://api.example.com/stream')),
        );

        expect(session.entries.length, 1);
        expect(session.entries.first.statusCode, 0);
        expect(session.entries.first.hasError, isFalse);

        streamCtrl.add([1, 2, 3, 4]);
        final sub = response.stream.listen((chunk) {});
        await sub.cancel();
        await streamCtrl.close();

        await _waitFor(() => session.entries.first.hasError);

        final entry = session.entries.first;
        expect(entry.hasError, isTrue);
        expect(entry.errorType, 'CancellationException');
        expect(
          entry.errorMessage,
          'Stream subscription was canceled by client.',
        );
      },
    );

    test(
      'cancellation during simulated throughput delay does not throw unhandled StateError',
      () async {
        session.setNetworkSimulation(NetworkSimulationProfile.slow3G);
        final streamCtrl = StreamController<List<int>>();
        final innerClient = _StreamingMockClient(streamCtrl);
        final client = InterceptlyHttpClient(innerClient, session);

        final response = await client.send(
          http.Request('GET', Uri.parse('https://api.example.com/throttle-cancel')),
        );

        streamCtrl.add(List.filled(100, 1));
        final sub = response.stream.listen((chunk) {});
        await sub.cancel();
        await streamCtrl.close();

        await Future<void>.delayed(const Duration(milliseconds: 150));

        await _waitFor(() => session.entries.first.hasError);
        final entry = session.entries.first;
        expect(entry.hasError, isTrue);
        expect(entry.errorType, 'CancellationException');
      },
    );

    test('records successful response when stream completes normally', () async {
      final streamCtrl = StreamController<List<int>>();
      final innerClient = _StreamingMockClient(streamCtrl);
      final client = InterceptlyHttpClient(innerClient, session);

      final response = await client.send(
        http.Request('GET', Uri.parse('https://api.example.com/data')),
      );

      final chunks = <List<int>>[];
      final completer = Completer<void>();
      response.stream.listen(
        chunks.add,
        onDone: completer.complete,
      );

      streamCtrl.add([10, 20, 30]);
      streamCtrl.add([40, 50]);
      await streamCtrl.close();
      await completer.future;

      await _waitFor(() => session.entries.isNotEmpty && session.entries.first.statusCode != 0);

      final entry = session.entries.first;
      expect(entry.statusCode, 200);
      expect(entry.hasError, isFalse);
      expect(entry.errorType, isNull);
    });

    test('records stream error when response stream emits error', () async {
      final streamCtrl = StreamController<List<int>>();
      final innerClient = _StreamingMockClient(streamCtrl);
      final client = InterceptlyHttpClient(innerClient, session);

      final response = await client.send(
        http.Request(
            'GET', Uri.parse('https://api.example.com/failing-stream')),
      );

      final completer = Completer<void>();
      response.stream.listen(
        (_) {},
        onError: (_) {
          if (!completer.isCompleted) completer.complete();
        },
      );

      streamCtrl.addError(Exception('stream broken mid-flight'));
      await streamCtrl.close();
      await completer.future;

      await _waitFor(() => session.entries.first.hasError);

      final entry = session.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, contains('Exception'));
      expect(entry.errorMessage, contains('stream broken mid-flight'));
    });

    test('records transport failure when inner send throws', () async {
      final innerClient = _FailingMockClient();
      final client = InterceptlyHttpClient(innerClient, session);

      await expectLater(
        () => client.send(
          http.Request('GET', Uri.parse('https://api.example.com/offline')),
        ),
        throwsA(isA<http.ClientException>()),
      );

      await _waitFor(() => session.entries.isNotEmpty && session.entries.first.hasError);

      final entry = session.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, 'ClientException');
      expect(entry.errorMessage, contains('Simulated network failure'));
    });

    test('offline simulation aborts request with SimulatedNetworkException and records failure in session', () async {
      session.setNetworkSimulation(NetworkSimulationProfile.offlineProfile);

      final client = InterceptlyHttpClient(_FixedMockClient(), session);

      await expectLater(
        () => client.get(Uri.parse('https://api.example.com/offline-sim')),
        throwsA(isA<SimulatedNetworkException>()),
      );

      await _waitFor(() => session.entries.isNotEmpty && session.entries.first.hasError);

      final entry = session.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, equals('SimulatedNetworkException'));
      expect(entry.errorMessage, contains('offline'));
    });
  });
}
