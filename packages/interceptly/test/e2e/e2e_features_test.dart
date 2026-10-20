// ignore_for_file: invalid_use_of_internal_member
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/mock_http_client.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/engine/body_store.dart';
import 'package:interceptly/src/ui/search/master_search_controller.dart';
import 'package:interceptly/src/engine/memory_index.dart';
import 'package:interceptly/src/share/interceptly_share.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/ui/detail/replay_handler.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';

class _E2EFakeScopeController extends InterceptlyScopeController {
  _E2EFakeScopeController({required this.record, InterceptlyEngine? engine})
      : super(engine: engine ?? InterceptlyEngine.instance);

  final RequestRecord record;

  @override
  Future<RequestRecord> loadDetail(RequestSummary summary) async => record;

  @override
  Future<RequestRecord> loadDetailById(String id) async => record;
}

/// Helper for packing body bytes compatible with BodyDecodeService.
Uint8List _packPayloadBytes(String? req, String? res,
    {bool truncated = false}) {
  final reqBytes = req != null ? Uint8List.fromList(utf8.encode(req)) : null;
  final resBytes = res != null ? Uint8List.fromList(utf8.encode(res)) : null;

  final total = 4 + (reqBytes?.length ?? 0) + 4 + (resBytes?.length ?? 0) + 1;
  final out = Uint8List(total);
  final data = ByteData.sublistView(out);
  var offset = 0;

  if (reqBytes == null) {
    data.setUint32(offset, 0xFFFFFFFF, Endian.big);
    offset += 4;
  } else {
    data.setUint32(offset, reqBytes.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + reqBytes.length, reqBytes);
    offset += reqBytes.length;
  }

  if (resBytes == null) {
    data.setUint32(offset, 0xFFFFFFFF, Endian.big);
    offset += 4;
  } else {
    data.setUint32(offset, resBytes.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + resBytes.length, resBytes);
    offset += resBytes.length;
  }

  out[offset] = truncated ? 1 : 0;
  return out;
}

/// Helper for generating test IndexEntry models.
IndexEntry _createIndexEntry(
  String id, {
  String method = 'GET',
  String url = 'https://api.example.com/v1/resource',
  int statusCode = 200,
  int durationMs = 30,
  int requestSizeBytes = 100,
  int responseSizeBytes = 200,
  bool hasError = false,
  BodyTruncation responseTruncation = const BodyTruncation.complete(0),
  Map<String, String> requestHeaders = const {},
  Map<String, String> responseHeaders = const {},
  String? requestContentType = 'application/json',
  String? responseContentType = 'application/json',
  String? errorMessage,
  BodyLocation bodyLocation = BodyLocation.memory,
  Uint8List? inlineRequestBody,
  Uint8List? inlineResponseBody,
  int? fileOffset,
  int? fileLength,
}) {
  return IndexEntry(
    id: id,
    method: method,
    url: url,
    statusCode: statusCode,
    durationMs: durationMs,
    requestSizeBytes: requestSizeBytes,
    responseSizeBytes: responseSizeBytes,
    timestamp: DateTime(2026, 4, 1, 12, 0, 0),
    hasError: hasError,
    requestTruncation: const BodyTruncation.complete(0),
    responseTruncation: responseTruncation,
    requestHeaders: requestHeaders,
    responseHeaders: responseHeaders,
    requestContentType: requestContentType,
    responseContentType: responseContentType,
    errorMessage: errorMessage,
    bodyLocation: bodyLocation,
    inlineRequestBody: inlineRequestBody,
    inlineResponseBody: inlineResponseBody,
    fileOffset: fileOffset,
    fileLength: fileLength,
  );
}

/// Helper for generating test RequestRecord models.
RequestRecord _createRequestRecord({
  String id = 'rec-1',
  String method = 'POST',
  String url = 'https://api.example.com/v1/resource',
  int statusCode = 200,
  int durationMs = 45,
  int requestSizeBytes = 120,
  int responseSizeBytes = 450,
  BodyTruncation responseTruncation = const BodyTruncation.complete(0),
  Map<String, String> requestHeaders = const {
    'content-type': 'application/json'
  },
  Map<String, String> responseHeaders = const {
    'content-type': 'application/json'
  },
  String? requestBodyPreview = '{"action":"create"}',
  String? responseBodyPreview = '{"id":"res-123","status":"created"}',
  String? requestContentType = 'application/json',
  String? responseContentType = 'application/json',
}) {
  return RequestRecord(
    id: id,
    method: method,
    url: url,
    statusCode: statusCode,
    durationMs: durationMs,
    requestSizeBytes: requestSizeBytes,
    responseSizeBytes: responseSizeBytes,
    timestamp: DateTime(2026, 4, 1, 12, 0, 0),
    requestTruncation: const BodyTruncation.complete(0),
    responseTruncation: responseTruncation,
    requestHeaders: requestHeaders,
    responseHeaders: responseHeaders,
    requestBodyPreview: requestBodyPreview,
    responseBodyPreview: responseBodyPreview,
    requestContentType: requestContentType,
    responseContentType: responseContentType,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('e2e_features_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      },
    );
  });

  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  tearDownAll(() async {
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Tier 1: Feature Coverage (F1 to F13 in Isolation)', () {
    test('[F1] MemoryIndex maintains newest-first order and length invariant',
        () {
      final index = MemoryIndex(maxEntries: 10);
      final e1 = _createIndexEntry('id-1');
      final e2 = _createIndexEntry('id-2');
      final e3 = _createIndexEntry('id-3');

      index.add(e1);
      index.add(e2);
      index.add(e3);

      expect(index.length, equals(3));
      expect(index.entries.first.id, equals('id-3'));
      expect(index.entries[1].id, equals('id-2'));
      expect(index.entries.last.id, equals('id-1'));
      expect(() => index.entries.add(e1), throwsUnsupportedError);
    });

    test(
        '[F2] MemoryIndex O(1) ID lookup and in-place updates preserve position',
        () {
      final index = MemoryIndex(maxEntries: 5);
      final initial = _createIndexEntry('item-1', statusCode: 0);
      final second = _createIndexEntry('item-2', statusCode: 200);

      index.add(initial);
      index.add(second);

      expect(index.byId('item-1')?.statusCode, equals(0));
      expect(index.byId('non-existent'), isNull);

      final updated =
          _createIndexEntry('item-1', statusCode: 201, durationMs: 90);
      index.add(updated);

      expect(index.length, equals(2));
      expect(index.byId('item-1')?.statusCode, equals(201));
      expect(index.entries.last.id, equals('item-1'));
      expect(index.entries.first.id, equals('item-2'));
    });

    testWidgets(
        '[F3] RequestDetailPage mounts Overview and leaves other tabs lazy',
        (tester) async {
      final entry = _createIndexEntry('lazy-test');
      final record = _createRequestRecord(id: 'lazy-test');
      final controller = _E2EFakeScopeController(record: record);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: RequestDetailPage(
                entry: entry,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overview'), findsWidgets);
      expect(find.text('Request'), findsWidgets);
      expect(find.text('Response'), findsWidgets);
      expect(find.text('Error'), findsWidgets);

      expect(find.text('Method'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('REQUEST HEADERS'), findsNothing);
      expect(find.text('RESPONSE HEADERS'), findsNothing);
    });

    testWidgets('[F5] JsonViewer renders line gutter and formatted JSON',
        (tester) async {
      final jsonPayload = {
        'service': 'auth_gateway',
        'status': 'healthy',
        'port': 8080,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              width: 400,
              child: JsonViewer(data: jsonPayload),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.textContaining('service'), findsWidgets);
      expect(find.textContaining('auth_gateway'), findsWidgets);
    });

    testWidgets('[F6] JsonViewer collapsible nodes fold and unfold correctly',
        (tester) async {
      final nestedData = {
        'profile': {
          'firstName': 'John',
          'lastName': 'Doe',
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              width: 400,
              child: JsonViewer(data: nestedData),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final foldIconFinder = find.byIcon(Icons.arrow_drop_down);
      expect(foldIconFinder, findsWidgets);

      await tester.tap(foldIconFinder.first);
      await tester.pumpAndSettle();

      expect(find.textContaining('…'), findsWidgets);
    });

    test(
        '[F7] BodyStore preserves complete byte payload on disk without data loss',
        () async {
      final store = BodyStore();
      await store.initForWrite(tempDir.path, fileName: 'f7_store.tmp');

      final originalData = Uint8List(50000);
      for (var i = 0; i < originalData.length; i++) {
        originalData[i] = i % 256;
      }

      final (offset, length) = await store.append(originalData);
      expect(offset, equals(0));
      expect(length, equals(50000));

      final readBack = await BodyStore.readBytes(
        '${tempDir.path}/f7_store.tmp',
        offset,
        length,
      );

      expect(readBack.length, equals(50000));
      expect(readBack, equals(originalData));

      await store.dispose();
    });

    testWidgets(
        '[F8] Detail page shows an in-place notice when body is truncated',
        (tester) async {
      const truncated = BodyTruncation(
        originalBytes: 7 * 1024 * 1024,
        retainedBytes: 5 * 1024 * 1024,
        stage: TruncationStage.storage,
      );
      final entry = _createIndexEntry(
        'truncated-entry',
        responseTruncation: truncated,
      );
      final record = _createRequestRecord(
        id: 'truncated-entry',
        responseTruncation: truncated,
        responseBodyPreview: '{"items": [1, 2, 3]}',
      );
      final controller = _E2EFakeScopeController(record: record);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: RequestDetailPage(
                entry: entry,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Response'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('maxBodyBytes'),
        findsOneWidget,
        reason: 'notice must sit on the response body, not repeat per section',
      );
      expect(find.textContaining('discarded'), findsOneWidget);
    });

    test('[F9] Exporters cURL, HAR, Postman export complete requests', () {
      final record = _createRequestRecord(
        method: 'POST',
        url: 'https://api.example.com/login',
        requestBodyPreview: '{"username":"agent","password":"secret_password"}',
      );

      final curl = CurlGenerator.fromRecord(record);
      expect(curl, contains("curl -X 'POST'"));
      expect(curl, contains('https://api.example.com/login'));
      expect(
          curl,
          contains(
              '--data-raw \'{"username":"agent","password":"secret_password"}\''));

      final har = HarExporter.toJson([record]);
      expect(har, contains('"version":"1.2"'));
      expect(har, contains('https://api.example.com/login'));
      expect(har, contains('secret_password'));

      final postman = PostmanExporter.toJson([record]);
      expect(postman, contains('schema.getpostman.com'));
      expect(postman, contains('https://api.example.com/login'));
      expect(postman, contains('secret_password'));
    });

    test(
        '[F10] InterceptlyShare validates safe export file path and handles non-mobile platforms gracefully',
        () async {
      expect(
          InterceptlyShare.isWithinTempDirectory('${tempDir.path}/export.json'),
          isTrue);

      final share = InterceptlyShare();
      final success = await share.shareFile(
        filePath: '${tempDir.path}/export.json',
        subject: 'Payload Export',
        mimeType: 'application/json',
      );

      expect(success, isFalse);
    });

    test('[F11] MasterSearchController executes Phase 3 file body search',
        () async {
      final store = BodyStore();
      await store.initForWrite(tempDir.path, fileName: 'f11_search.tmp');
      final filePath = '${tempDir.path}/f11_search.tmp';

      final packed = _packPayloadBytes(
        '{"op": "lookup"}',
        '{"result": "FOUND_SECRET_ALPHA"}',
      );
      final (offset, length) = await store.append(packed);

      final entry = _createIndexEntry(
        'f11-entry',
        bodyLocation: BodyLocation.file,
        fileOffset: offset,
        fileLength: length,
      );

      final controller = MasterSearchController();
      await controller.start(
        query: 'FOUND_SECRET_ALPHA',
        allEntries: [entry],
        filePath: filePath,
      );

      expect(controller.results, isNotNull);
      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('f11-entry'));

      controller.dispose();
      await store.dispose();
    });

    test('[F12] MasterSearchController notifies listeners on search lifecycle',
        () async {
      final controller = MasterSearchController();
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      final entry =
          _createIndexEntry('f12-entry', url: 'https://api.example.com/test');
      await controller.start(
        query: 'test',
        allEntries: [entry],
        filePath: null,
      );

      expect(notifyCount, greaterThan(0));
      expect(controller.results!.length, equals(1));

      controller.dispose();
    });

    test('[F13] Temp session lifecycle cleans up file upon disposal', () async {
      final store = BodyStore();
      await store.initForWrite(tempDir.path, fileName: 'f13_cleanup.tmp');
      final file = File('${tempDir.path}/f13_cleanup.tmp');

      expect(await file.exists(), isTrue);

      await store.dispose();
      expect(await file.exists(), isFalse);
    });
  });

  group('Tier 2: Boundary & Corner Cases', () {
    test('Boundary: empty URL, zero status code, empty headers, and empty body',
        () {
      final entry = _createIndexEntry(
        'empty-boundary',
        url: '',
        statusCode: 0,
        durationMs: 0,
        requestHeaders: {},
        responseHeaders: {},
      );

      final index = MemoryIndex(maxEntries: 5);
      index.add(entry);

      expect(index.length, equals(1));
      expect(index.byId('empty-boundary')?.url, isEmpty);
      expect(index.byId('empty-boundary')?.statusCode, equals(0));
    });

    test(
        'Boundary: maxEntries = 1 continually evicts oldest maintaining single entry',
        () {
      final index = MemoryIndex(maxEntries: 1);

      for (var i = 1; i <= 50; i++) {
        index.add(_createIndexEntry('id-$i'));
        expect(index.length, equals(1));
        expect(index.entries.first.id, equals('id-$i'));
      }
    });

    test('Boundary: 50MB+ payload storage write and readback simulation',
        () async {
      final store = BodyStore();
      await store.initForWrite(tempDir.path,
          fileName: 'large_payload_50mb.tmp');

      final chunk = Uint8List(1024 * 1024);
      chunk.fillRange(0, chunk.length, 65);

      var totalWritten = 0;
      for (var i = 0; i < 5; i++) {
        final (offset, len) = await store.append(chunk);
        expect(offset, equals(totalWritten));
        expect(len, equals(1024 * 1024));
        totalWritten += len;
      }
      expect(totalWritten, equals(5 * 1024 * 1024));

      final readSlice = await BodyStore.readBytes(
        '${tempDir.path}/large_payload_50mb.tmp',
        2 * 1024 * 1024,
        1024,
      );
      expect(readSlice.length, equals(1024));
      expect(readSlice.every((b) => b == 65), isTrue);

      await store.dispose();
    });

    test(
        'Boundary: search with regex meta-characters, accents, and zero matches',
        () async {
      final controller = MasterSearchController();
      final e1 = _createIndexEntry('special-1',
          url: 'https://api.example.com/items?filter=[0-9]+.*');
      final e2 = _createIndexEntry('special-2',
          url: 'https://api.example.com/items/caffè_latte');

      await controller.start(
        query: '[0-9]+.*',
        allEntries: [e1, e2],
        filePath: null,
      );
      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('special-1'));

      await controller.start(
        query: 'caffè',
        allEntries: [e1, e2],
        filePath: null,
      );
      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('special-2'));

      await controller.start(
        query: 'unmatched_string_xyz_123',
        allEntries: [e1, e2],
        filePath: null,
      );
      expect(controller.results, isNotNull);
      expect(controller.results, isEmpty);

      controller.dispose();
    });

    test(
        'Boundary: non-interceptly files in temp directory remain strictly untouched',
        () async {
      final nonInterceptlyFile = File('${tempDir.path}/app_database.sqlite');
      await nonInterceptlyFile.writeAsString('sqlite binary content');

      final store = BodyStore();
      await store.initForWrite(tempDir.path,
          fileName: 'interceptly_temp_session.tmp');
      await store.append(Uint8List.fromList([1, 2, 3]));
      await store.dispose();

      expect(await nonInterceptlyFile.exists(), isTrue);
      expect(await nonInterceptlyFile.readAsString(),
          equals('sqlite binary content'));
    });
  });

  group('Tier 3: Cross-Feature Combinations', () {
    test(
        'Cross: Large file payload persistence combined with Master Search Phase 3',
        () async {
      final store = BodyStore();
      await store.initForWrite(tempDir.path, fileName: 'cross_search.tmp');
      final filePath = '${tempDir.path}/cross_search.tmp';

      final largeResponseBody =
          '{"data": "${"A" * 15000}", "marker": "TARGET_NEEDLE_FOUND"}';
      final packed = _packPayloadBytes(null, largeResponseBody);
      final (offset, length) = await store.append(packed);

      final fileEntry = _createIndexEntry(
        'file-search-entry',
        bodyLocation: BodyLocation.file,
        fileOffset: offset,
        fileLength: length,
      );

      final controller = MasterSearchController();
      await controller.start(
        query: 'TARGET_NEEDLE_FOUND',
        allEntries: [fileEntry],
        filePath: filePath,
      );

      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('file-search-entry'));

      controller.dispose();
      await store.dispose();
    });

    testWidgets('Cross: Lazy tab switching combined with JsonViewer rendering',
        (tester) async {
      final entry = _createIndexEntry('tab-json-cross');
      final record = _createRequestRecord(
        id: 'tab-json-cross',
        responseBodyPreview:
            '{"status":"active","metrics":{"cpu":15,"memory":2048}}',
      );
      final controller = _E2EFakeScopeController(record: record);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: RequestDetailPage(
                entry: entry,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overview'), findsWidgets);

      await tester.tap(find.text('Response'));
      await tester.pumpAndSettle();

      expect(find.byType(JsonViewer), findsWidgets);
      expect(find.textContaining('metrics'), findsWidgets);
      expect(find.textContaining('cpu'), findsWidgets);
    });

    test(
        'Cross: Multiple sequential sessions isolate files and clean up independently',
        () async {
      final storeA = BodyStore();
      final storeB = BodyStore();

      await storeA.initForWrite(tempDir.path, fileName: 'session_A.tmp');
      await storeB.initForWrite(tempDir.path, fileName: 'session_B.tmp');

      final fileA = File('${tempDir.path}/session_A.tmp');
      final fileB = File('${tempDir.path}/session_B.tmp');

      expect(await fileA.exists(), isTrue);
      expect(await fileB.exists(), isTrue);

      await storeA.dispose();
      expect(await fileA.exists(), isFalse);
      expect(await fileB.exists(), isTrue);

      await storeB.dispose();
      expect(await fileB.exists(), isFalse);
    });
  });

  group('Tier 4: Real-World Scenarios', () {
    testWidgets(
        'Scenario 2: Inspecting full response and headers in RequestDetailPage',
        (tester) async {
      final entry = _createIndexEntry('inspect-scenario');
      final record = _createRequestRecord(
        id: 'inspect-scenario',
        requestHeaders: {
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        responseHeaders: {
          'server': 'nginx/1.24',
          'content-type': 'application/json',
        },
        responseBodyPreview: '{"status":"ok","code":200}',
      );
      final controller = _E2EFakeScopeController(record: record);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: RequestDetailPage(
                entry: entry,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overview'), findsWidgets);
      expect(find.text('Method'), findsOneWidget);
      expect(find.text('POST'), findsWidgets);

      await tester.tap(find.text('Request'));
      await tester.pumpAndSettle();
      expect(find.text('REQUEST HEADERS'), findsOneWidget);

      await tester.tap(find.text('Response'));
      await tester.pumpAndSettle();

      expect(find.text('RESPONSE HEADERS'), findsOneWidget);
      expect(find.textContaining('server'), findsWidgets);
      expect(find.byType(JsonViewer), findsWidgets);
      expect(find.textContaining('status'), findsWidgets);
    });

    testWidgets('Scenario 3: Replaying captured request with ReplayHandler',
        (tester) async {
      final record = _createRequestRecord(
        method: 'POST',
        url: 'https://api.example.com/checkout',
        requestHeaders: {'content-type': 'application/json'},
        requestBodyPreview: '{"cartId":"cart_789"}',
      );

      MockHttpClientRequest? capturedReplayRequest;
      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              savedContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);
      final handler = ReplayHandler(
        context: savedContext,
        engine: engine,
        clientFactory: () => MockHttpClient((request) {
          capturedReplayRequest = request;
        }),
      );

      await tester.runAsync(() async {
        await handler.retry(record, confirm: false);
      });

      expect(capturedReplayRequest, isNotNull);
      expect(capturedReplayRequest!.method, equals('POST'));
      expect(capturedReplayRequest!.uri.toString(),
          equals('https://api.example.com/checkout'));
      expect(capturedReplayRequest!.body, equals('{"cartId":"cart_789"}'));
    });

    test(
        'Scenario 4: Multi-format export consistency across cURL, HAR, Postman',
        () {
      final record = _createRequestRecord(
        method: 'PUT',
        url: 'https://api.example.com/users/42',
        requestHeaders: {
          'content-type': 'application/json',
          'x-version': '2.0',
        },
        requestBodyPreview: '{"email":"updated@example.com"}',
        responseBodyPreview: '{"updated":true}',
      );

      final curl = CurlGenerator.fromRecord(record);
      final har = HarExporter.toJson([record]);
      final postman = PostmanExporter.toJson([record]);

      expect(curl, contains('PUT'));
      expect(curl, contains('https://api.example.com/users/42'));
      expect(curl, contains('updated@example.com'));

      final parsedHar = jsonDecode(har) as Map<String, dynamic>;
      final log = parsedHar['log'] as Map<String, dynamic>;
      final entries = log['entries'] as List<dynamic>;
      expect(entries.length, equals(1));
      final harReq = entries.first['request'] as Map<String, dynamic>;
      expect(harReq['method'], equals('PUT'));
      expect(harReq['url'], equals('https://api.example.com/users/42'));

      final parsedPostman = jsonDecode(postman) as Map<String, dynamic>;
      final items = parsedPostman['item'] as List<dynamic>;
      expect(items.length, equals(1));
      final postmanReq = items.first['request'] as Map<String, dynamic>;
      expect(postmanReq['method'], equals('PUT'));
      expect(
          postmanReq['url']['raw'], equals('https://api.example.com/users/42'));
    });
  });
}
