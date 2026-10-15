import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/export/curl_generator.dart';
import 'package:interceptly/src/export/har_exporter.dart';
import 'package:interceptly/src/export/postman_exporter.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/request_record.dart';
import 'package:interceptly/src/session/inspector_session.dart';
import 'package:interceptly/src/share/interceptly_share.dart';
import 'package:interceptly/src/ui/detail/replay_handler.dart';
import 'package:interceptly/src/ui/detail/share_handler.dart';

import '../helpers/mock_http_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('export_hardening_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getTemporaryDirectory') {
        return tempDir.path;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('CurlGenerator hardening', () {
    test('rejects shell injection methods with ArgumentError', () {
      final record = _record(method: 'GET; rm -rf /');
      expect(() => CurlGenerator.fromRecord(record), throwsArgumentError);
    });

    test('rejects CRLF in HTTP method', () {
      final record = _record(method: 'GET\r\nX-Injected: true');
      expect(() => CurlGenerator.fromRecord(record), throwsArgumentError);
    });

    test('rejects non-standard HTTP methods', () {
      final record = _record(method: 'FOO_BAR');
      expect(() => CurlGenerator.fromRecord(record), throwsArgumentError);
    });

    test('strips CRLF from request headers', () {
      final record = _record(
        method: 'GET',
        requestHeaders: {
          'X-Good': 'value',
          'X-Injected\r\n': 'bad\r\nheader',
        },
      );
      final curl = CurlGenerator.fromRecord(record);
      expect(curl, isNot(contains('\r')));
      expect(curl, isNot(contains('\n')));
      expect(curl, contains("-H 'X-Injected: badheader'"));
    });

    test('outputs headers raw without redaction', () {
      final record = _record(
        requestHeaders: {
          'Authorization': 'Bearer secret-token',
          'Content-Type': 'application/json',
        },
      );
      final curl = CurlGenerator.fromRecord(record);
      expect(curl, contains('secret-token'));
      expect(curl, contains("-H 'Authorization: Bearer secret-token'"));
      expect(curl, contains("-H 'Content-Type: application/json'"));
    });
  });

  group('HarExporter hardening', () {
    test('contains required HAR 1.2 fields: pages, cache, timings, queryString', () {
      final record = _record(
        durationMs: 120,
        url: 'https://api.example.com/items?category=books&page=2',
      );
      final har = HarExporter.toMap([record]);
      final log = har['log'] as Map<String, Object?>;

      expect(log.containsKey('pages'), isTrue);
      expect(log['pages'], isA<List>());

      final entries = log['entries'] as List;
      expect(entries, isNotEmpty);
      final entry = entries.first as Map<String, Object?>;

      expect(entry.containsKey('cache'), isTrue);
      expect(entry['cache'], isA<Map>());

      final timings = entry['timings'] as Map<String, Object?>;
      expect(timings['blocked'], -1);
      expect(timings['dns'], -1);
      expect(timings['connect'], -1);
      expect(timings['send'], 0);
      expect(timings['wait'], 120);
      expect(timings['receive'], 0);
      expect(timings['ssl'], -1);

      final req = entry['request'] as Map<String, Object?>;
      final queryString = req['queryString'] as List;
      expect(queryString, containsAll([
        {'name': 'category', 'value': 'books'},
        {'name': 'page', 'value': '2'},
      ]));
    });

    test('formats startedDateTime in UTC ISO 8601', () {
      final localTime = DateTime(2026, 5, 1, 10, 30);
      final record = _record(timestamp: localTime);
      final har = HarExporter.toMap([record]);
      final entries = (har['log'] as Map)['entries'] as List;
      final started = (entries.first as Map)['startedDateTime'] as String;

      expect(started, equals(localTime.toUtc().toIso8601String()));
      expect(started.endsWith('Z'), isTrue);
    });

    test('guards status <= 0 to avoid breaking HAR viewers', () {
      final abortedRecord = _record(statusCode: 0);
      final har = HarExporter.toMap([abortedRecord]);
      final entries = (har['log'] as Map)['entries'] as List;
      final res = (entries.first as Map)['response'] as Map;

      expect(res['status'], 0);
      expect(res['statusText'], isNotEmpty);
    });

    test('outputs headers and query parameters raw without redaction', () {
      final record = _record(
        url: 'https://api.example.com/data?token=supersecret&page=1',
        requestHeaders: {'Authorization': 'Bearer confidential'},
      );
      final har = HarExporter.toMap([record]);
      final entries = (har['log'] as Map)['entries'] as List;
      final req = (entries.first as Map)['request'] as Map;

      final headers = (req['headers'] as List).cast<Map<String, String>>();
      expect(
        headers.any((h) => h['name'] == 'Authorization' && h['value'] == 'Bearer confidential'),
        isTrue,
      );

      final query = (req['queryString'] as List).cast<Map<String, String>>();
      expect(
        query.any((q) => q['name'] == 'token' && q['value'] == 'supersecret'),
        isTrue,
      );
      expect(
        query.any((q) => q['name'] == 'page' && q['value'] == '1'),
        isTrue,
      );
    });
  });

  group('PostmanExporter hardening', () {
    test('preserves custom port in URL structure', () {
      final record = _record(url: 'https://api.example.com:8443/v1/users');
      final postman = PostmanExporter.toMap([record]);
      final items = postman['item'] as List;
      final req = (items.first as Map)['request'] as Map;
      final url = req['url'] as Map;

      expect(url['port'], '8443');
      expect(url['protocol'], 'https');
      expect(url['host'], ['api', 'example', 'com']);
    });

    test('strips userinfo from URL for security', () {
      final record = _record(url: 'https://admin:secret123@api.example.com/v1/data');
      final postman = PostmanExporter.toMap([record]);
      final items = postman['item'] as List;
      final req = (items.first as Map)['request'] as Map;
      final url = req['url'] as Map;

      expect(url['raw'], isNot(contains('secret123')));
      expect(url['raw'], 'https://api.example.com/v1/data');
      expect(url['host'], ['api', 'example', 'com']);
    });

    test('warns on empty or invalid multipart/form-data body', () {
      final record = _record(
        requestContentType: 'multipart/form-data; boundary=xyz',
        requestBodyPreview: null,
      );
      final postman = PostmanExporter.toMap([record]);
      final items = postman['item'] as List;
      final req = (items.first as Map)['request'] as Map;
      final body = req['body'] as Map?;

      expect(body, isNotNull);
      expect(body!['mode'], 'formdata');
      final formdata = body['formdata'] as List;
      expect(formdata, isNotEmpty);
      final first = formdata.first as Map;
      expect(first['value'].toString().toLowerCase(), contains('multipart'));
    });

    test('outputs headers raw without redaction', () {
      final record = _record(
        requestHeaders: {
          'Authorization': 'Bearer token-abc',
          'X-Api-Key': 'key-xyz',
        },
      );
      final postman = PostmanExporter.toMap([record]);
      final items = postman['item'] as List;
      final req = (items.first as Map)['request'] as Map;
      final headers = (req['header'] as List).cast<Map<String, String>>();

      expect(
        headers.any((h) => h['key'] == 'Authorization' && h['value'] == 'Bearer token-abc'),
        isTrue,
      );
      expect(
        headers.any((h) => h['key'] == 'X-Api-Key' && h['value'] == 'key-xyz'),
        isTrue,
      );
    });
  });

  group('ReplayHandler SSRF & security guards', () {
    testWidgets('blocks non-http schemes (file://, ftp://)', (tester) async {
      MockHttpClientRequest? capturedRequest;
      final record = _record(method: 'GET', url: 'file:///etc/passwd');

      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (ctx) {
            savedContext = ctx;
            return const SizedBox();
          }),
        ),
      );

      final session = InspectorSession();
      addTearDown(session.dispose);

      final handler = ReplayHandler(
        context: savedContext,
        session: session,
        clientFactory: () => MockHttpClient((req) => capturedRequest = req),
      );

      await tester.runAsync(() async {
        await handler.retry(record);
      });
      expect(capturedRequest, isNull);
    });

    testWidgets('blocks loopback IP and localhost', (tester) async {
      MockHttpClientRequest? capturedRequest;
      final session = InspectorSession();
      addTearDown(session.dispose);

      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (ctx) {
            savedContext = ctx;
            return const SizedBox();
          }),
        ),
      );

      final handler = ReplayHandler(
        context: savedContext,
        session: session,
        clientFactory: () => MockHttpClient((req) => capturedRequest = req),
      );

      await tester.runAsync(() async {
        await handler.retry(_record(method: 'GET', url: 'http://localhost:8080/admin'));
        expect(capturedRequest, isNull);

        await handler.retry(_record(method: 'GET', url: 'http://127.0.0.1:3000/keys'));
        expect(capturedRequest, isNull);

        await handler.retry(_record(method: 'GET', url: 'http://[::1]:80/status'));
        expect(capturedRequest, isNull);
      });
    });

    testWidgets('blocks cloud metadata IP 169.254.169.254', (tester) async {
      MockHttpClientRequest? capturedRequest;
      final session = InspectorSession();
      addTearDown(session.dispose);

      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (ctx) {
            savedContext = ctx;
            return const SizedBox();
          }),
        ),
      );

      final handler = ReplayHandler(
        context: savedContext,
        session: session,
        clientFactory: () => MockHttpClient((req) => capturedRequest = req),
      );

      await tester.runAsync(() async {
        await handler.retry(_record(
          method: 'GET',
          url: 'http://169.254.169.254/latest/meta-data/',
        ));
      });
      expect(capturedRequest, isNull);
    });

    testWidgets('blocks RFC1918 and .internal/.local hosts', (tester) async {
      MockHttpClientRequest? capturedRequest;
      final session = InspectorSession();
      addTearDown(session.dispose);

      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (ctx) {
            savedContext = ctx;
            return const SizedBox();
          }),
        ),
      );

      final handler = ReplayHandler(
        context: savedContext,
        session: session,
        clientFactory: () => MockHttpClient((req) => capturedRequest = req),
      );

      await tester.runAsync(() async {
        for (final url in [
          'http://192.168.1.1/admin',
          'http://10.0.0.5/keys',
          'http://172.16.4.2/status',
          'http://172.31.255.255/status',
          'http://svc.internal/data',
          'http://printer.local/info',
        ]) {
          capturedRequest = null;
          await handler.retry(_record(method: 'GET', url: url));
          expect(capturedRequest, isNull, reason: 'should block $url');
        }
      });
    });

    testWidgets('retry prompts for GET too', (tester) async {
      MockHttpClientRequest? capturedRequest;
      final session = InspectorSession();
      addTearDown(session.dispose);

      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (ctx) {
            savedContext = ctx;
            return const SizedBox();
          }),
        ),
      );

      var dialogPrompted = false;
      final handler = ReplayHandler(
        context: savedContext,
        session: session,
        clientFactory: () => MockHttpClient((req) => capturedRequest = req),
        confirmDialog: (ctx, method) async {
          dialogPrompted = true;
          return true;
        },
      );

      await tester.runAsync(() async {
        await handler.retry(_record(method: 'GET', url: 'https://api.example.com/items'));
        expect(dialogPrompted, isTrue);
        expect(capturedRequest, isNotNull);
      });
    });

    testWidgets('prompts confirmation on non-idempotent methods', (tester) async {
      MockHttpClientRequest? capturedRequest;
      final session = InspectorSession();
      addTearDown(session.dispose);

      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (ctx) {
            savedContext = ctx;
            return const SizedBox();
          }),
        ),
      );

      var dialogPrompted = false;
      var userApproved = false;

      final handler = ReplayHandler(
        context: savedContext,
        session: session,
        clientFactory: () => MockHttpClient((req) => capturedRequest = req),
        confirmDialog: (ctx, method) async {
          dialogPrompted = true;
          return userApproved;
        },
      );

      final postRecord = _record(method: 'POST', url: 'https://api.example.com/pay');

      await tester.runAsync(() async {
        userApproved = false;
        await handler.retry(postRecord);
        expect(dialogPrompted, isTrue);
        expect(capturedRequest, isNull);

        dialogPrompted = false;
        userApproved = true;
        await handler.retry(postRecord);
        expect(dialogPrompted, isTrue);
        expect(capturedRequest, isNotNull);
      });
    });
  });

  group('InterceptlyShare & ShareHandler temp file lifecycle', () {
    test('InterceptlyShare throws ArgumentError for paths outside temp directory', () {
      final share = InterceptlyShare();
      expect(
        () => share.shareFile(filePath: '/etc/passwd'),
        throwsArgumentError,
      );
      expect(
        () => share.shareFile(filePath: '/tmp/../etc/shadow'),
        throwsArgumentError,
      );
    });

    test('InterceptlyShare throws on file exceeding max size', () async {
      final largeFile = File('${tempDir.path}/huge.har');
      await largeFile.writeAsBytes(Uint8List(100));

      final share = InterceptlyShare();
      await expectLater(
        share.shareFile(
          filePath: largeFile.path,
          maxFileSizeBytes: 50,
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('exceeds'))),
      );

      if (await largeFile.exists()) {
        await largeFile.delete();
      }
    });

    testWidgets('ShareHandler deletes temp HAR file after export in finally', (tester) async {
      late BuildContext savedContext;
      final fabKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: FloatingActionButton(
              key: fabKey,
              onPressed: () {},
            ),
            body: Builder(builder: (ctx) {
              savedContext = ctx;
              return const SizedBox();
            }),
          ),
        ),
      );

      String? sharedFilePath;
      final mockShare = _MockInterceptlyShare((path) async {
        sharedFilePath = path;
        expect(File(path).existsSync(), isTrue);
        return true;
      });

      final handler = ShareHandler.withShare(
        context: savedContext,
        fabKey: fabKey,
        share: mockShare,
      );

      final record = _record(method: 'GET', url: 'https://api.example.com/test');
      await tester.runAsync(() async {
        await handler.exportHarFile(record);
      });

      expect(sharedFilePath, isNotNull);
      expect(File(sharedFilePath!).existsSync(), isFalse);
    });

    testWidgets('ShareHandler deletes temp Postman file after export in finally', (tester) async {
      late BuildContext savedContext;
      final fabKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: FloatingActionButton(
              key: fabKey,
              onPressed: () {},
            ),
            body: Builder(builder: (ctx) {
              savedContext = ctx;
              return const SizedBox();
            }),
          ),
        ),
      );

      String? sharedFilePath;
      final mockShare = _MockInterceptlyShare((path) async {
        sharedFilePath = path;
        expect(File(path).existsSync(), isTrue);
        return true;
      });

      final handler = ShareHandler.withShare(
        context: savedContext,
        fabKey: fabKey,
        share: mockShare,
      );

      final record = _record(method: 'POST', url: 'https://api.example.com/test');
      await tester.runAsync(() async {
        await handler.exportPostmanRecords([record]);
      });

      expect(sharedFilePath, isNotNull);
      expect(File(sharedFilePath!).existsSync(), isFalse);
    });
  });
}

class _MockInterceptlyShare extends Fake implements InterceptlyShare {
  _MockInterceptlyShare(this.onShare);

  final Future<bool> Function(String filePath) onShare;

  @override
  Future<bool> shareFile({
    required String filePath,
    String? subject,
    String? text,
    String? mimeType,
    Rect? origin,
    int maxFileSizeBytes = 50 * 1024 * 1024,
  }) async {
    return onShare(filePath);
  }
}

RequestRecord _record({
  String method = 'GET',
  String url = 'https://api.example.com/test',
  int statusCode = 200,
  int durationMs = 50,
  DateTime? timestamp,
  Map<String, String>? requestHeaders,
  Map<String, String>? responseHeaders,
  String? requestBodyPreview,
  String? responseBodyPreview,
  String? requestContentType,
  String? responseContentType,
}) {
  return RequestRecord(
    id: 'test-id',
    method: method,
    url: url,
    statusCode: statusCode,
    durationMs: durationMs,
    requestSizeBytes: 0,
    responseSizeBytes: 0,
    timestamp: timestamp ?? DateTime(2026, 1, 1),
    requestHeaders: requestHeaders ?? {},
    responseHeaders: responseHeaders ?? {},
    requestContentType: requestContentType,
    responseContentType: responseContentType,
    requestBodyPreview: requestBodyPreview,
    responseBodyPreview: responseBodyPreview,
    requestTruncation: const BodyTruncation.complete(0),
    responseTruncation: const BodyTruncation.complete(0),
  );
}
