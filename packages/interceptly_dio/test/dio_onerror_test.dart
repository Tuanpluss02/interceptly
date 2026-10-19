import 'dart:async';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Interceptly interceptly;

  setUp(() async {
    await Interceptly.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp('interceptly_dio_onerror');
    _mockTempDir(() async => tempDir.path);
    interceptly = Interceptly.instance;
    await interceptly.initialize();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Dio onError semantics and body capture', () {
    test('badResponse (404) passes through to caller and hasError is false',
        () async {
      final dio = Dio()
        ..httpClientAdapter = _FixedAdapter(
          statusCode: 404,
          responseBody: '{"error":"Not Found"}',
        );
      dio.interceptors.add(InterceptlyDioInterceptor());

      DioException? caught;
      try {
        await dio.get<dynamic>('https://api.example.com/notfound');
      } on DioException catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);
      expect(caught!.type, equals(DioExceptionType.badResponse));
      expect(caught.response?.statusCode, equals(404));

      await _waitFor(
        () =>
            interceptly.entries.isNotEmpty && interceptly.entries.first.statusCode != 0,
      );
      expect(interceptly.entries.length, equals(1));
      final entry = interceptly.entries.first;
      expect(entry.statusCode, equals(404));
      expect(entry.hasError, isFalse);
      expect(entry.errorType, isNull);

      final detail = await interceptly.loadDetail(entry);
      expect(detail.responseBodyPreview, contains('Not Found'));
    });

    test('badResponse (500) passes through to caller and hasError is false',
        () async {
      final dio = Dio()
        ..httpClientAdapter = _FixedAdapter(
          statusCode: 500,
          responseBody: '{"error":"Server Error"}',
        );
      dio.interceptors.add(InterceptlyDioInterceptor());

      DioException? caught;
      try {
        await dio.post<dynamic>(
          'https://api.example.com/fail',
          data: '{"input":123}',
        );
      } on DioException catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);
      expect(caught!.type, equals(DioExceptionType.badResponse));
      expect(caught.response?.statusCode, equals(500));

      await _waitFor(
        () =>
            interceptly.entries.isNotEmpty && interceptly.entries.first.statusCode != 0,
      );
      expect(interceptly.entries.length, equals(1));
      final entry = interceptly.entries.first;
      expect(entry.statusCode, equals(500));
      expect(entry.hasError, isFalse);
      expect(entry.errorType, isNull);
    });

    test('connectionTimeout passes through and hasError is true', () async {
      final dio = Dio()
        ..httpClientAdapter = _ThrowingAdapter(
          (options) => DioException.connectionTimeout(
            timeout: const Duration(seconds: 5),
            requestOptions: options,
          ),
        );
      dio.interceptors.add(InterceptlyDioInterceptor());

      DioException? caught;
      try {
        await dio.get<dynamic>('https://api.example.com/timeout');
      } on DioException catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);
      expect(caught!.type, equals(DioExceptionType.connectionTimeout));

      await _waitFor(
          () => interceptly.entries.isNotEmpty && interceptly.entries.first.hasError);
      expect(interceptly.entries.length, equals(1));
      final entry = interceptly.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, equals(DioExceptionType.connectionTimeout.name));
    });

    test('cancel passes through and hasError is true', () async {
      final cancelToken = CancelToken();
      final dio = Dio()
        ..httpClientAdapter = _ThrowingAdapter(
          (options) => DioException.requestCancelled(
            requestOptions: options,
            reason: 'User canceled request',
          ),
        );
      dio.interceptors.add(InterceptlyDioInterceptor());

      DioException? caught;
      try {
        await dio.get<dynamic>(
          'https://api.example.com/cancel',
          cancelToken: cancelToken,
        );
      } on DioException catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);
      expect(caught!.type, equals(DioExceptionType.cancel));

      await _waitFor(
          () => interceptly.entries.isNotEmpty && interceptly.entries.first.hasError);
      expect(interceptly.entries.length, equals(1));
      final entry = interceptly.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, equals(DioExceptionType.cancel.name));
    });

    test('active CancelToken mid-flight cancellation records errorType cancel',
        () async {
      final cancelToken = CancelToken();
      final dio = Dio()
        ..httpClientAdapter = _ThrowingAdapter((options) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            message: 'Request cancelled with CancelToken',
          );
        });
      dio.interceptors.add(InterceptlyDioInterceptor());

      DioException? caught;
      try {
        final future = dio.get<dynamic>(
          'https://api.example.com/active-cancel',
          cancelToken: cancelToken,
        );
        cancelToken.cancel('cancelled by caller');
        await future;
      } on DioException catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);
      expect(caught!.type, equals(DioExceptionType.cancel));

      await _waitFor(
          () => interceptly.entries.isNotEmpty && interceptly.entries.first.hasError);
      expect(interceptly.entries.length, equals(1));
      final entry = interceptly.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, equals('cancel'));
    });

    test('captures String request body larger than 50KB synchronously',
        () async {
      final largeString = 'X' * (60 * 1024);
      final dio = Dio()
        ..httpClientAdapter = _FixedAdapter(
          statusCode: 200,
          responseBody: '{"status":"ok"}',
        );
      dio.interceptors.add(InterceptlyDioInterceptor());

      final response = await dio.post<dynamic>(
        'https://api.example.com/large-body',
        data: largeString,
        options: Options(contentType: 'text/plain'),
      );
      expect(response.statusCode, equals(200));

      await _waitFor(() =>
          interceptly.entries.isNotEmpty && interceptly.entries.first.statusCode != 0);
      expect(interceptly.entries.length, equals(1));
      final entry = interceptly.entries.first;
      expect(entry.requestSizeBytes, greaterThanOrEqualTo(60 * 1024));

      final detail = await interceptly.loadDetail(entry);
      expect(detail.requestBodyPreview, isNotNull);
      expect(detail.requestBodyPreview!.length, greaterThan(1000));
    });

    test('captures String response body larger than 50KB synchronously',
        () async {
      final largeResponse = 'Y' * (64 * 1024);
      final dio = Dio()
        ..httpClientAdapter = _FixedAdapter(
          statusCode: 200,
          responseBody: largeResponse,
          headers: {
            Headers.contentTypeHeader: ['text/plain'],
          },
        );
      dio.interceptors.add(InterceptlyDioInterceptor());

      final response =
          await dio.get<dynamic>('https://api.example.com/large-res');
      expect(response.statusCode, equals(200));

      await _waitFor(() =>
          interceptly.entries.isNotEmpty && interceptly.entries.first.statusCode != 0);
      expect(interceptly.entries.length, equals(1));
      final entry = interceptly.entries.first;
      expect(entry.responseSizeBytes, greaterThanOrEqualTo(64 * 1024));
    });

    test(
        'cleans up _contextKey and _reqBytesKey from RequestOptions.extra after request',
        () async {
      final options = Options(
        extra: <String, dynamic>{
          'interceptly_req_bytes': Uint8List(16),
          'custom_user_key': 'keep_me',
        },
      );
      final dio = Dio()
        ..httpClientAdapter = _FixedAdapter(
          statusCode: 200,
          responseBody: '{"ok":true}',
        );
      dio.interceptors.add(InterceptlyDioInterceptor());

      final response = await dio.get<dynamic>(
        'https://api.example.com/extra-cleanup',
        options: options,
      );
      expect(response.statusCode, equals(200));

      expect(
          response.requestOptions.extra.containsKey('interceptly_http_scope'),
          isFalse);
      expect(
          response.requestOptions.extra.containsKey('interceptly_http_context'),
          isFalse);
      expect(response.requestOptions.extra.containsKey('interceptly_req_bytes'),
          isFalse);
      expect(
          response.requestOptions.extra['custom_user_key'], equals('keep_me'));
    });
  });
}
