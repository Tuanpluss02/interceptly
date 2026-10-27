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
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw StateError('Timed out waiting for capture');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

typedef _ServerRequest = ({String method, String path, String body});

/// Starts a loopback server that redirects `/start` and records the real
/// requests received for both hops.
Future<HttpServer> _startRedirectServer(
  List<_ServerRequest> requests, {
  required int redirectStatus,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final body = await utf8.decoder.bind(request).join();
    requests.add((
      method: request.method,
      path: request.uri.path,
      body: body,
    ));

    if (request.uri.path == '/start') {
      request.response.statusCode = redirectStatus;
      request.response.headers.set(HttpHeaders.locationHeader, '/final');
      await request.response.close();
      return;
    }

    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write('{"ok":true}');
    await request.response.close();
  });
  return server;
}

class _MapBodyAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"echo":true}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Verifies the captured request is the original outbound tuple, not a
/// hybrid of the final redirect URL with the original method/body/headers.
///
/// Dart's HttpClient only follows 307/308 for GET/HEAD, so the 307 case uses
/// GET; the 303 case is the POST-to-GET rewrite that creates the hybrid.
Future<void> _expectAuthenticRedirectCapture({
  required int redirectStatus,
  required String expectedFinalMethod,
  required String requestMethod,
  String? requestBody,
}) async {
  final requests = <_ServerRequest>[];
  final server = await _startRedirectServer(
    requests,
    redirectStatus: redirectStatus,
  );
  addTearDown(() => server.close(force: true));

  final baseUrl = 'http://127.0.0.1:${server.port}';
  final dio = Dio();
  dio.interceptors.add(InterceptlyDioInterceptor());

  final response = requestMethod == 'POST'
      ? await dio.post<dynamic>(
          '$baseUrl/start',
          data: requestBody,
          options: Options(
            contentType: 'text/plain',
            headers: {'X-Trace': 'original'},
          ),
        )
      : await dio.get<dynamic>(
          '$baseUrl/start',
          options: Options(headers: {'X-Trace': 'original'}),
        );
  expect(response.statusCode, equals(200));

  await _waitFor(
    () =>
        Interceptly.instance.entries.isNotEmpty &&
        Interceptly.instance.entries.first.statusCode == 200,
  );

  expect(requests.length, equals(2));
  expect(requests[0].method, equals(requestMethod));
  expect(requests[0].path, equals('/start'));
  expect(requests[0].body, equals(requestBody ?? ''));
  expect(requests[1].method, equals(expectedFinalMethod));
  expect(requests[1].path, equals('/final'));

  expect(Interceptly.instance.entries.length, equals(1));
  final entry = Interceptly.instance.entries.first;
  expect(entry.method, equals(requestMethod));
  expect(entry.url, equals('$baseUrl/start'));
  expect(entry.requestHeaders['X-Trace'], equals('original'));

  final detail = await Interceptly.instance.loadDetail(entry);
  if (requestBody != null) {
    expect(
      entry.requestSizeBytes,
      equals(utf8.encode(requestBody).length),
    );
    expect(detail.requestBodyPreview, contains(requestBody));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  HttpOverrides? previousHttpOverrides;

  setUp(() async {
    await Interceptly.resetForTesting();
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('dio_redirect_amend_');
    _mockTempDir(() async => tempDir.path);
    await Interceptly.instance.initialize();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
    HttpOverrides.global = previousHttpOverrides;
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Dio redirect amend regression', () {
    test('303 redirect keeps the authentic original POST tuple', () async {
      await _expectAuthenticRedirectCapture(
        redirectStatus: 303,
        expectedFinalMethod: 'GET',
        requestMethod: 'POST',
        requestBody: 'original-body',
      );
    });

    test('307 redirect keeps the authentic original GET tuple', () async {
      await _expectAuthenticRedirectCapture(
        redirectStatus: 307,
        expectedFinalMethod: 'GET',
        requestMethod: 'GET',
      );
    });

    test('dio request headers are snapshotted against later mutation',
        () async {
      Map<String, dynamic>? capturedHeaders;
      final dio = Dio()..httpClientAdapter = _MapBodyAdapter();
      dio.interceptors.add(InterceptlyDioInterceptor());
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedHeaders = Map.of(options.headers);
            handler.next(options);
          },
        ),
      );

      final headers = <String, dynamic>{'X-Trace': 'original'};
      await dio.get<dynamic>(
        'https://api.example.com/trace',
        options: Options(headers: headers),
      );

      await _waitFor(() => Interceptly.instance.entries.isNotEmpty);
      expect(Interceptly.instance.entries.length, equals(1));
      final entry = Interceptly.instance.entries.first;
      expect(entry.requestHeaders['X-Trace'], equals('original'));
      expect(capturedHeaders?['X-Trace'], equals('original'));
    });

    test('dio Map body throttles via encoded bytes length', () async {
      final dio = Dio()..httpClientAdapter = _MapBodyAdapter();
      dio.interceptors.add(InterceptlyDioInterceptor());

      final response = await dio.post<dynamic>(
        'https://api.example.com/echo',
        data: {'hello': 'world', 'count': 3},
      );
      expect(response.statusCode, equals(200));

      await _waitFor(
        () =>
            Interceptly.instance.entries.isNotEmpty &&
            Interceptly.instance.entries.first.statusCode == 200,
      );

      final entry = Interceptly.instance.entries.first;
      final detail = await Interceptly.instance.loadDetail(entry);
      expect(detail.responseBodyPreview, contains('echo'));
      final encoded = utf8.encode(jsonEncode({'hello': 'world', 'count': 3}));
      expect(encoded.length, greaterThan(0));
      expect(entry.requestSizeBytes, equals(encoded.length));
    });
  });
}
