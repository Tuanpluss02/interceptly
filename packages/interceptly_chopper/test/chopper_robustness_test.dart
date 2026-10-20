import 'dart:async';
import 'dart:io';

import 'package:chopper/chopper.dart' as chopper;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_chopper/interceptly_chopper.dart';

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

class _FakeChain<T> implements chopper.Chain<T> {
  _FakeChain(this.request, this.handler);

  @override
  final chopper.Request request;
  final FutureOr<chopper.Response<T>> Function(chopper.Request) handler;

  @override
  FutureOr<chopper.Response<T>> proceed(chopper.Request request) =>
      handler(request);
}

class _Model {
  const _Model();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Chopper interceptor never breaks the request', () {
    late Directory tempDir;
    late Interceptly interceptly;

    setUp(() async {
      await Interceptly.resetForTesting();
      tempDir = await Directory.systemTemp
          .createTemp('interceptly_chopper_robustness');
      _mockTempDir(() async => tempDir.path);
      interceptly = Interceptly.instance;
      await interceptly.initialize();
    });

    tearDown(() async {
      await Interceptly.resetForTesting();
      try {
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('multipart base request does not throw', () async {
      final interceptor = InterceptlyChopperInterceptor();
      final request = chopper.Request(
        'POST',
        Uri.parse('https://api.example.com/upload'),
        Uri.parse('https://api.example.com'),
        multipart: true,
      );
      final base = http.MultipartRequest('POST', request.url)
        ..fields['name'] = 'alice';

      final chain = _FakeChain<String>(
        request,
        (req) => chopper.Response(
          http.Response('ok', 200, request: base),
          'ok',
        ),
      );

      final response = await interceptor.intercept(chain);
      expect(response.statusCode, 200);
    });

    test('response without base request does not throw', () async {
      final interceptor = InterceptlyChopperInterceptor();
      final request = chopper.Request(
        'GET',
        Uri.parse('https://api.example.com/mock'),
        Uri.parse('https://api.example.com'),
      );

      final chain = _FakeChain<String>(
        request,
        (req) => chopper.Response(http.Response('ok', 200), 'ok'),
      );

      final response = await interceptor.intercept(chain);
      expect(response.statusCode, 200);
    });

    test('captures raw response bytes, not the converted model', () async {
      final interceptor = InterceptlyChopperInterceptor();
      final request = chopper.Request(
        'GET',
        Uri.parse('https://api.example.com/model'),
        Uri.parse('https://api.example.com'),
      );

      final chain = _FakeChain<_Model>(
        request,
        (req) => chopper.Response(
          http.Response(
            '{"a":1}',
            200,
            headers: {'content-type': 'application/json'},
            request: http.Request('GET', req.url),
          ),
          const _Model(),
        ),
      );

      await interceptor.intercept(chain);
      await _waitFor(
        () =>
            interceptly.entries.isNotEmpty &&
            interceptly.entries.first.statusCode != 0,
      );

      final detail = await interceptly.loadDetail(interceptly.entries.first);
      expect(detail.responseBodyPreview, '{"a":1}');
    });
  });
}
