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
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _ToStringThrows {
  @override
  String toString() => throw StateError('boom');
}

class _FixedAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"streamed":true}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('interceptly_dio_robustness');
    _mockTempDir(() async => tempDir.path);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Dio interceptor never breaks the request', () {
    late InspectorSession session;

    setUp(() async {
      session = InspectorSession();
      await session.initialize();
    });

    tearDown(() => session.dispose());

    test('response whose data cannot be serialised still completes', () async {
      final dio = Dio()..httpClientAdapter = _FixedAdapter();
      dio.interceptors.addAll([
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              data: _ToStringThrows(),
              statusCode: 200,
            ),
            true,
          ),
        ),
        InterceptlyDioInterceptor(session),
      ]);

      final response = await dio
          .get<dynamic>('https://api.example.com/bad')
          .timeout(const Duration(seconds: 3));
      expect(response.statusCode, 200);
    });

    test('stream responses are not captured as "Instance of"', () async {
      final dio = Dio()..httpClientAdapter = _FixedAdapter();
      dio.interceptors.add(InterceptlyDioInterceptor(session));

      final response = await dio.get<ResponseBody>(
        'https://api.example.com/stream',
        options: Options(responseType: ResponseType.stream),
      );
      await response.data!.stream.drain<void>();

      await _waitFor(
        () =>
            session.entries.isNotEmpty && session.entries.first.statusCode != 0,
      );
      final detail = await session.loadDetail(session.entries.first);
      expect(detail.responseBodyPreview ?? '', isNot(contains('Instance of')));
    });
  });
}
