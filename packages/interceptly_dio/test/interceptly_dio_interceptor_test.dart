import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_dio/interceptly_dio.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void _mockTempDir(Future<Object?> Function() handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, (call) async {
    if (call.method == 'getTemporaryDirectory') return handler();
    return null;
  });
}

Future<void> _waitFor(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 4));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _FixedAdapter implements HttpClientAdapter {
  _FixedAdapter({
    this.statusCode = 200,
    this.responseBody = '{"ok":true}',
    this.headers,
  });

  final int statusCode;
  final String responseBody;
  final Map<String, List<String>>? headers;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      responseBody,
      statusCode,
      headers: headers ??
          {
            Headers.contentTypeHeader: ['application/json'],
          },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ThrowingAdapter implements HttpClientAdapter {
  _ThrowingAdapter(this.createError);

  final Object Function(RequestOptions options) createError;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw createError(options);
  }

  @override
  void close({bool force = false}) {}
}

class _SpyHttpTrafficCollector implements HttpTrafficCollector {
  _SpyHttpTrafficCollector([InspectorSession? session])
      : session = session ?? InspectorSession.instance;

  final InspectorSession session;
  HttpRequestContext? nextContext;
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

  group('InterceptlyDioInterceptor contracts and injection', () {
    test('implements HttpCaptureAdapter', () {
      final interceptor = InterceptlyDioInterceptor();
      expect(interceptor, isA<HttpCaptureAdapter>());
    });

    test('uses shared session and DefaultHttpTrafficCollector by default', () {
      final interceptor = InterceptlyDioInterceptor();
      expect(interceptor.session, same(InspectorSession.instance));
      expect(interceptor.collector, isA<DefaultHttpTrafficCollector>());
      final defaultCollector =
          interceptor.collector as DefaultHttpTrafficCollector;
      expect(defaultCollector.session, same(InspectorSession.instance));
    });

    test('constructs with custom session', () {
      final session = InspectorSession();
      final interceptor = InterceptlyDioInterceptor(session);
      expect(interceptor.session, same(session));
      expect(interceptor.collector, isA<DefaultHttpTrafficCollector>());
      final defaultCollector =
          interceptor.collector as DefaultHttpTrafficCollector;
      expect(defaultCollector.session, same(session));
    });

    test('constructs with custom DefaultHttpTrafficCollector', () {
      final session = InspectorSession();
      final collector = DefaultHttpTrafficCollector(session);
      final interceptor = InterceptlyDioInterceptor(null, collector);
      expect(interceptor.session, same(session));
      expect(interceptor.collector, same(collector));
    });

    test(
        'constructs with custom HttpTrafficCollector and falls back to shared session',
        () {
      final spyCollector = _SpyHttpTrafficCollector();
      final interceptor = InterceptlyDioInterceptor(null, spyCollector);
      expect(interceptor.session, same(InspectorSession.instance));
      expect(interceptor.collector, same(spyCollector));
    });

    test('constructs with both custom session and custom HttpTrafficCollector',
        () {
      final session = InspectorSession();
      final spyCollector = _SpyHttpTrafficCollector();
      final interceptor = InterceptlyDioInterceptor(session, spyCollector);
      expect(interceptor.session, same(session));
      expect(interceptor.collector, same(spyCollector));
    });
  });

  group('Lifecycle delegation to HttpTrafficCollector', () {
    test(
        'onRequest delegates to collector.startRequest and stores context in extra',
        () async {
      final spy = _SpyHttpTrafficCollector();
      final interceptor = InterceptlyDioInterceptor(null, spy);

      final dio = Dio()..httpClientAdapter = _FixedAdapter();
      dio.interceptors.add(interceptor);

      await dio.post<dynamic>(
        'https://api.example.com/create',
        data: {'name': 'test'},
        options: Options(headers: {'X-Api-Key': '123'}),
      );

      expect(spy.startRequestCalls.length, equals(1));
      final call = spy.startRequestCalls.first;
      expect(call['method'], equals('POST'));
      expect(call['uri'], equals(Uri.parse('https://api.example.com/create')));
      expect(
          (call['headers'] as Map<String, String>)['X-Api-Key'], equals('123'));
      expect(call['bodyBytes'], isNotNull);
      expect(utf8.decode(call['bodyBytes'] as Uint8List),
          contains('"name":"test"'));
    });

    test(
        'onResponse delegates to collector.completeResponse with context and response details',
        () async {
      final spy = _SpyHttpTrafficCollector();
      final interceptor = InterceptlyDioInterceptor(null, spy);

      final dio = Dio()
        ..httpClientAdapter = _FixedAdapter(
          statusCode: 201,
          responseBody: '{"created":true}',
          headers: {
            'content-type': ['application/json'],
            'x-custom-res': ['header-val'],
          },
        );
      dio.interceptors.add(interceptor);

      final res = await dio.get<dynamic>('https://api.example.com/item');
      expect(res.statusCode, equals(201));

      expect(spy.completeResponseCalls.length, equals(1));
      final call = spy.completeResponseCalls.first;
      expect(call['statusCode'], equals(201));
      expect(call['context'], isA<HttpRequestContext>());
      expect((call['headers'] as Map<String, String>)['x-custom-res'],
          equals('header-val'));
      expect(utf8.decode(call['bodyBytes'] as Uint8List),
          equals('{"created":true}'));
    });

    test(
        'onError delegates to collector.completeResponse on badResponse with response',
        () async {
      final spy = _SpyHttpTrafficCollector();
      final interceptor = InterceptlyDioInterceptor(null, spy);

      final dio = Dio()
        ..httpClientAdapter = _ThrowingAdapter(
          (options) => DioException.badResponse(
            statusCode: 404,
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 404,
              data: '{"error":"not found"}',
              headers: Headers.fromMap({
                'content-type': ['application/json'],
              }),
            ),
          ),
        );
      dio.interceptors.add(interceptor);

      await expectLater(
        dio.get<dynamic>('https://api.example.com/notfound'),
        throwsA(isA<DioException>()),
      );

      expect(spy.completeResponseCalls.length, equals(1));
      final call = spy.completeResponseCalls.first;
      expect(call['statusCode'], equals(404));
      expect(call['context'], isA<HttpRequestContext>());
      expect(call['bodyBytes'], isNotNull);
      expect(utf8.decode(call['bodyBytes'] as Uint8List),
          contains('not found'));
    });

    test('onError creates fallback context when missing from extra', () async {
      final spy = _SpyHttpTrafficCollector();
      final interceptor = InterceptlyDioInterceptor(null, spy);

      final dio = Dio()
        ..httpClientAdapter = _ThrowingAdapter(
          (_) => DioException.connectionError(
            requestOptions: RequestOptions(
              path: 'https://api.example.com/fallback',
              method: 'DELETE',
              headers: {'x-fallback': 'yes'},
            ),
            reason: 'Network dropped',
          ),
        );
      dio.interceptors.add(interceptor);

      await expectLater(
        dio.delete<dynamic>('https://api.example.com/fallback'),
        throwsA(isA<DioException>()),
      );

      expect(spy.failRequestCalls.length, equals(1));
      final call = spy.failRequestCalls.first;
      expect(call['context'], isA<HttpRequestContext>());
      final context = call['context'] as HttpRequestContext;
      expect(context.method, equals('DELETE'));
      expect(context.url, equals('https://api.example.com/fallback'));
      expect(context.requestHeaders['x-fallback'], equals('yes'));
      expect(call['errorType'], equals(DioExceptionType.connectionError.name));
    });

    test(
        'SimulatedNetworkException in startRequest rejects with DioException.connectionError',
        () async {
      final spy = _SpyHttpTrafficCollector()..throwSimulatedException = true;
      final interceptor = InterceptlyDioInterceptor(null, spy);

      final dio = Dio()..httpClientAdapter = _FixedAdapter();
      dio.interceptors.add(interceptor);

      DioException? caughtException;
      try {
        await dio.get<dynamic>('https://api.example.com/simulated');
      } on DioException catch (e) {
        caughtException = e;
      }

      expect(caughtException, isNotNull);
      expect(caughtException!.type, equals(DioExceptionType.connectionError));
      expect(caughtException.error, isA<SimulatedNetworkException>());
      expect(
          caughtException.message, contains('Pre-request simulation: offline'));
    });
  });

  group('Integration with InspectorSession and network simulation', () {
    late InspectorSession session;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dio_interceptor_test_');
      _mockTempDir(() async => tempDir.path);
      session = InspectorSession();
      await session.initialize();
    });

    tearDown(() async {
      await session.dispose();
      try {
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('captures end-to-end GET request and response in session', () async {
      final dio = Dio()
        ..httpClientAdapter = _FixedAdapter(responseBody: '{"id":42}');
      dio.interceptors.add(InterceptlyDioInterceptor(session));

      final response =
          await dio.get<dynamic>('https://api.example.com/items/42');
      expect(response.statusCode, equals(200));

      await _waitFor(
        () =>
            session.entries.isNotEmpty &&
            session.entries.first.statusCode == 200,
      );

      expect(session.entries.length, equals(1));
      final entry = session.entries.first;
      expect(entry.method, equals('GET'));
      expect(entry.url, equals('https://api.example.com/items/42'));
      expect(entry.statusCode, equals(200));
      expect(entry.hasError, isFalse);

      final detail = await session.loadDetail(entry);
      expect(detail.responseBodyPreview, contains('"id":42'));
    });

    test('captures end-to-end failed request with error details in session',
        () async {
      final dio = Dio()
        ..httpClientAdapter = _ThrowingAdapter(
          (options) => DioException.connectionTimeout(
            timeout: const Duration(seconds: 5),
            requestOptions: options,
          ),
        );
      dio.interceptors.add(InterceptlyDioInterceptor(session));

      await expectLater(
        dio.get<dynamic>('https://api.example.com/slow'),
        throwsA(isA<DioException>()),
      );

      await _waitFor(
        () => session.entries.isNotEmpty && session.entries.first.hasError,
      );

      expect(session.entries.length, equals(1));
      final entry = session.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, equals(DioExceptionType.connectionTimeout.name));
    });

    test(
        'offline simulation aborts request with DioException and records failure in session',
        () async {
      session.setNetworkSimulation(NetworkSimulationProfile.offlineProfile);

      final dio = Dio()..httpClientAdapter = _FixedAdapter();
      dio.interceptors.add(InterceptlyDioInterceptor(session));

      DioException? caughtException;
      try {
        await dio.get<dynamic>('https://api.example.com/offline');
      } on DioException catch (e) {
        caughtException = e;
      }

      expect(caughtException, isNotNull);
      expect(caughtException!.type, equals(DioExceptionType.connectionError));
      expect(caughtException.error, isA<SimulatedNetworkException>());

      await _waitFor(
        () => session.entries.isNotEmpty && session.entries.first.hasError,
      );

      expect(session.entries.length, equals(1));
      final entry = session.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, equals('SimulatedNetworkException'));
    });
  });
}
