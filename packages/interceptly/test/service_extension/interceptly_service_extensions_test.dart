import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/service_extension/interceptly_service_extensions.dart';

const MethodChannel _channel =
    MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InterceptlyEngine engine;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('service_extensions_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tempDir.path;
      return null;
    });

    engine = InterceptlyEngine();
    await engine.initialize();
  });

  tearDown(() async {
    await engine.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  RawCapture createCapture({
    required String id,
    String method = 'GET',
    String url = 'https://api.example.com/items',
    int statusCode = 200,
    String requestBody = '{"query":"flutter"}',
    String responseBody = '{"items":[{"id":1,"name":"Widget"}]}',
    Map<String, String>? requestHeaders,
    Map<String, String>? responseHeaders,
  }) {
    final reqBytes = Uint8List.fromList(utf8.encode(requestBody));
    final resBytes = Uint8List.fromList(utf8.encode(responseBody));
    return RawCapture(
      id: id,
      method: method,
      url: url,
      statusCode: statusCode,
      durationMs: 45,
      timestamp: DateTime.now(),
      requestHeaders:
          requestHeaders ?? const {'content-type': 'application/json'},
      responseHeaders:
          responseHeaders ?? const {'content-type': 'application/json'},
      requestContentType: 'application/json',
      responseContentType: 'application/json',
      requestBodyBytes: TransferableTypedData.fromList([reqBytes]),
      responseBodyBytes: TransferableTypedData.fromList([resBytes]),
      requestSizeBytes: reqBytes.length,
      responseSizeBytes: resBytes.length,
    );
  }

  group('InterceptlyServiceExtensions pure handlers', () {
    test('handlePing returns extensionApiVersion: 1 and session info', () {
      final res = InterceptlyServiceExtensions.handlePing(
        engine: engine,
        parameters: {},
        isEnabled: true,
      );

      expect(res['status'], 'ok');
      expect(res['extensionApiVersion'], 1);
      expect(res['entryCount'], 0);
      expect(res['networkSimulation'], 'No throttling');
    });

    test('throws ServiceExtensionException when isEnabled is false', () {
      expect(
        () => InterceptlyServiceExtensions.handlePing(
          engine: engine,
          parameters: {},
          isEnabled: false,
        ),
        throwsA(
          isA<ServiceExtensionException>().having(
            (e) => e.errorCode,
            'errorCode',
            equals(-32000), // ServiceExtensionResponse.extensionError
          ),
        ),
      );
    });

    test(
        'handleListRequests supports filtering, searching, and since_id cursor',
        () async {
      engine.record(createCapture(
          id: 'req_1', statusCode: 200, url: 'https://api.example.com/users'));
      engine.record(createCapture(
          id: 'req_2',
          statusCode: 404,
          url: 'https://api.example.com/missing'));
      engine.record(createCapture(
          id: 'req_3', statusCode: 500, url: 'https://api.example.com/crash'));

      // Wait for pipeline processing
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // 1. List all
      final all = await InterceptlyServiceExtensions.handleListRequests(
        engine: engine,
        parameters: {'status_filter': 'all'},
      );
      final allList = all['requests'] as List;
      expect(allList.length, 3);

      // 2. Filter failed only (4xx, 5xx)
      final failed = await InterceptlyServiceExtensions.handleListRequests(
        engine: engine,
        parameters: {'status_filter': 'failed'},
      );
      final failedList = failed['requests'] as List;
      expect(failedList.length, 2);
      expect(failedList.map((e) => e['statusCode']), containsAll([404, 500]));

      // 3. Search query
      final search = await InterceptlyServiceExtensions.handleListRequests(
        engine: engine,
        parameters: {'search': 'missing'},
      );
      final searchList = search['requests'] as List;
      expect(searchList.length, 1);
      expect(searchList.first['id'], 'req_2');

      // 4. Cursor pagination since_id (newest-first, entries after req_2)
      final since = await InterceptlyServiceExtensions.handleListRequests(
        engine: engine,
        parameters: {'since_id': 'req_2'},
      );
      final sinceList = since['requests'] as List;
      expect(sinceList.any((e) => e['id'] == 'req_2'), isFalse);
    });

    test(
        'handleListRequests searches across headers and body and returns matchScopes',
        () async {
      engine.record(createCapture(
        id: 'req_hdr',
        statusCode: 200,
        url: 'https://api.example.com/data',
        requestHeaders: {'X-Custom-Auth': 'token-auth-xyz'},
      ));
      engine.record(createCapture(
        id: 'req_body',
        statusCode: 200,
        url: 'https://api.example.com/payload',
        responseBody: '{"order_status":"COMPLETED_OK"}',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Match header
      final headerSearch =
          await InterceptlyServiceExtensions.handleListRequests(
        engine: engine,
        parameters: {'search': 'token-auth-xyz'},
      );
      final headerList = headerSearch['requests'] as List;
      expect(headerList.length, 1);
      expect(headerList.first['id'], 'req_hdr');
      expect(headerList.first['matchScopes'], contains('headers'));

      // Match body
      final bodySearch = await InterceptlyServiceExtensions.handleListRequests(
        engine: engine,
        parameters: {'search': 'COMPLETED_OK'},
      );
      final bodyList = bodySearch['requests'] as List;
      expect(bodyList.length, 1);
      expect(bodyList.first['id'], 'req_body');
      expect(bodyList.first['matchScopes'], contains('body'));

      // Skips body when search_body is false
      final noBodySearch =
          await InterceptlyServiceExtensions.handleListRequests(
        engine: engine,
        parameters: {'search': 'COMPLETED_OK', 'search_body': 'false'},
      );
      expect(noBodySearch['requests'], isEmpty);
    });

    test(
        'handleGetRequestDetail loads detail, handles part, offset, and max_chars',
        () async {
      const longBody =
          'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      engine.record(createCapture(
        id: 'req_detail_1',
        statusCode: 200,
        responseBody: longBody,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Missing ID -> invalidParams (-32602)
      expect(
        () => InterceptlyServiceExtensions.handleGetRequestDetail(
          engine: engine,
          parameters: {},
        ),
        throwsA(
          isA<ServiceExtensionException>().having(
            (e) => e.errorCode,
            'errorCode',
            equals(-32602), // ServiceExtensionResponse.invalidParams
          ),
        ),
      );

      // Full part with slice
      final detail = await InterceptlyServiceExtensions.handleGetRequestDetail(
        engine: engine,
        parameters: {
          'id': 'req_detail_1',
          'part': 'response_body',
          'offset': '0',
          'max_chars': '10',
        },
      );

      expect(detail['id'], 'req_detail_1');
      expect(detail['responseBody'], 'abcdefghij');
      expect(detail['isTruncated'], isTrue);
      expect(detail['totalChars'], longBody.length);
      expect(detail['remainingChars'], longBody.length - 10);

      // Continuation chunk with offset: 10
      final chunk2 = await InterceptlyServiceExtensions.handleGetRequestDetail(
        engine: engine,
        parameters: {
          'id': 'req_detail_1',
          'part': 'response_body',
          'offset': '10',
          'max_chars': '10',
        },
      );
      expect(chunk2['responseBody'], 'klmnopqrst');
    });

    test('handleSetNetworkSimulation applies profile', () {
      final res = InterceptlyServiceExtensions.handleSetNetworkSimulation(
        engine: engine,
        parameters: {'profile': 'slow3g'},
      );

      expect(res['status'], 'ok');
      expect(res['networkSimulation'], 'Slow 3G');
      expect(engine.networkSimulation, NetworkSimulationProfile.slow3G);
    });

    test('handleClearTraffic clears session entries', () async {
      engine.record(createCapture(id: 'req_c1'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(engine.entries.length, 1);

      final res = await InterceptlyServiceExtensions.handleClearTraffic(
        engine: engine,
        parameters: {},
      );
      expect(res['status'], 'ok');
      expect(engine.entries.isEmpty, isTrue);
    });

    test('handleExportCurl generates valid curl string', () async {
      engine.record(createCapture(
        id: 'req_curl_1',
        method: 'POST',
        url: 'https://api.example.com/login',
        requestBody: '{"username":"dev"}',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final res = await InterceptlyServiceExtensions.handleExportCurl(
        engine: engine,
        parameters: {'id': 'req_curl_1'},
      );

      expect(res['id'], 'req_curl_1');
      expect(res['curl'], contains("curl -X 'POST'"));
      expect(res['curl'], contains("'https://api.example.com/login'"));
      expect(res['curl'], contains('{"username":"dev"}'));
    });

    test('register is idempotent and enable/disable toggles extension state',
        () {
      InterceptlyServiceExtensions.register(engine);
      expect(InterceptlyServiceExtensions.isRegistered, isTrue);
      expect(InterceptlyServiceExtensions.isEnabled, isTrue);

      // Calling register second time does not throw
      expect(
          () => InterceptlyServiceExtensions.register(engine), returnsNormally);

      InterceptlyServiceExtensions.disable();
      expect(InterceptlyServiceExtensions.isEnabled, isFalse);

      InterceptlyServiceExtensions.enable();
      expect(InterceptlyServiceExtensions.isEnabled, isTrue);
    });
  });
}
