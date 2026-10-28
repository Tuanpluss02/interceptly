// ignore_for_file: invalid_use_of_internal_member
@Tags(['stress'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';

class _MockSessionScopeController extends InterceptlyScopeController {
  _MockSessionScopeController({required this.record, InterceptlyEngine? engine})
      : super(engine: engine ?? InterceptlyEngine.instance);

  final RequestRecord record;

  @override
  Future<RequestRecord> loadDetail(RequestSummary summary) async => record;

  @override
  Future<RequestRecord> loadDetailById(String id) async => record;
}

RequestRecord _createRecord({
  required String id,
  String method = 'GET',
  String url = 'https://api.example.com/test',
  int statusCode = 200,
  int durationMs = 20,
  int requestSizeBytes = 0,
  int responseSizeBytes = 0,
  Map<String, String> requestHeaders = const {},
  Map<String, String> responseHeaders = const {},
  String? requestContentType,
  String? responseContentType,
  String? requestBodyPreview,
  String? responseBodyPreview,
  Uint8List? requestBodyBytes,
  Uint8List? responseBodyBytes,
  BodyTruncation responseTruncation = const BodyTruncation.complete(0),
}) {
  return RequestRecord(
    id: id,
    method: method,
    url: url,
    statusCode: statusCode,
    durationMs: durationMs,
    requestSizeBytes: requestSizeBytes,
    responseSizeBytes: responseSizeBytes,
    timestamp: DateTime.now(),
    requestHeaders: requestHeaders,
    responseHeaders: responseHeaders,
    requestContentType: requestContentType,
    responseContentType: responseContentType,
    requestBodyPreview: requestBodyPreview,
    responseBodyPreview: responseBodyPreview,
    requestBodyBytes: requestBodyBytes,
    responseBodyBytes: responseBodyBytes,
    requestTruncation: const BodyTruncation.complete(0),
    responseTruncation: responseTruncation,
  );
}

IndexEntry _createIndexEntry(RequestRecord r) {
  return IndexEntry(
    id: r.id,
    method: r.method,
    url: r.url,
    statusCode: r.statusCode,
    durationMs: r.durationMs,
    requestSizeBytes: r.requestSizeBytes,
    responseSizeBytes: r.responseSizeBytes,
    timestamp: r.timestamp,
    hasError: r.hasError,
    requestTruncation: r.requestTruncation,
    responseTruncation: r.responseTruncation,
    bodyLocation: BodyLocation.memory,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('Milestone 2: Settings and Decoupling Constants', () {
    test(
        'InterceptlySettings defaults decouple storage limit from UI preview limit',
        () {
      const settings = InterceptlySettings();
      expect(settings.maxBodyBytes, equals(5 * 1024 * 1024));
      expect(settings.maxUiPreviewBytes, equals(2 * 1024 * 1024));

      final updated = settings.copyWith(
        maxBodyBytes: 0,
        maxUiPreviewBytes: 1024 * 1024,
      );
      expect(updated.maxBodyBytes, equals(0));
      expect(updated.maxUiPreviewBytes, equals(1024 * 1024));
    });

    test('RequestRecord holds intact payload bytes and UI truncation flag', () {
      final reqBytes = Uint8List.fromList(utf8.encode('{"action":"test"}'));
      final resBytes = Uint8List.fromList(utf8.encode('{"status":"ok"}'));

      final record = _createRecord(
          id: 'rec_m2_1',
          method: 'POST',
          requestBodyBytes: reqBytes,
          responseBodyBytes: resBytes,
          responseTruncation: const BodyTruncation(
            originalBytes: 7000000,
            retainedBytes: 2000000,
            stage: TruncationStage.preview,
          ));

      expect(record.requestBodyBytes, equals(reqBytes));
      expect(record.responseBodyBytes, equals(resBytes));
      expect(record.responseTruncation.isPreviewOnly, isTrue);
    });
  });

  group('Milestone 2: Exporter Data Integrity', () {
    test(
        'CurlGenerator prioritizes intact requestBodyBytes over preview string',
        () {
      final rawPayload = '{"full_key":"full_value_exceeding_preview"}';
      final record = _createRecord(
        id: 'rec_curl_1',
        method: 'POST',
        url: 'https://api.example.com/order',
        requestHeaders: {'content-type': 'application/json'},
        requestBodyPreview: '{"full_key":"truncated...',
        requestBodyBytes: Uint8List.fromList(utf8.encode(rawPayload)),
      );

      final curl = CurlGenerator.fromRecord(record);
      expect(curl, contains(rawPayload));
      expect(curl, isNot(contains('truncated...')));
    });

    test('HarExporter utilizes intact requestBodyBytes and responseBodyBytes',
        () {
      final intactReq = '{"req_param":12345}';
      final intactRes = '{"res_result":"complete_untruncated_data"}';

      final record = _createRecord(
        id: 'rec_har_1',
        method: 'PUT',
        url: 'https://api.example.com/resource',
        requestHeaders: {'content-type': 'application/json'},
        responseHeaders: {'content-type': 'application/json'},
        requestBodyBytes: Uint8List.fromList(utf8.encode(intactReq)),
        responseBodyBytes: Uint8List.fromList(utf8.encode(intactRes)),
        requestBodyPreview: '{"req_param":...',
        responseBodyPreview: '{"res_result":...',
      );

      final harJson = HarExporter.toJson([record]);
      final parsed = jsonDecode(harJson) as Map<String, dynamic>;
      final entry =
          (parsed['log']['entries'] as List).first as Map<String, dynamic>;

      final postText = entry['request']['postData']['text'] as String;
      final resText = entry['response']['content']['text'] as String;

      expect(postText, equals(intactReq));
      expect(resText, equals(intactRes));
    });

    test('PostmanExporter utilizes intact requestBodyBytes', () {
      final intactBody = '{"postman_test":true,"large_payload":"abcdefghij"}';
      final record = _createRecord(
        id: 'rec_postman_1',
        method: 'POST',
        url: 'https://api.example.com/items',
        requestHeaders: {'content-type': 'application/json'},
        requestBodyBytes: Uint8List.fromList(utf8.encode(intactBody)),
        requestBodyPreview: '{"postman_test":...',
      );

      final postmanJson = PostmanExporter.toJson([record]);
      final parsed = jsonDecode(postmanJson) as Map<String, dynamic>;
      final item = (parsed['item'] as List).first as Map<String, dynamic>;
      final rawBody = item['request']['body']['raw'] as String;

      expect(rawBody, equals(intactBody));
    });
  });

  group('Milestone 2: Virtualized JsonViewer', () {
    testWidgets(
        'renders 5,000 lines cleanly using dual virtualized ListView.builders with itemExtent 18.0',
        (tester) async {
      final largeMap = {
        for (int i = 1; i <= 5000; i++) 'key_$i': 'val_$i',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              width: 400,
              child: JsonViewer(data: largeMap),
            ),
          ),
        ),
      );
      await settleWithRealIsolate(tester);

      final listViews = find.byType(ListView);
      expect(listViews, findsNWidgets(2));

      final firstListView = tester.widget<ListView>(listViews.first);
      final secondListView = tester.widget<ListView>(listViews.last);
      expect(firstListView.itemExtent, equals(18.0));
      expect(secondListView.itemExtent, equals(18.0));

      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('navigates to target line on search match jumping',
        (tester) async {
      final searchData = {
        for (int i = 1; i <= 100; i++)
          'item_$i': i == 50 ? 'TARGET_VALUE' : 'val_$i',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              width: 400,
              child: JsonViewer(
                data: searchData,
                searchQuery: 'TARGET_VALUE',
                activeGlobalIndex: 0,
              ),
            ),
          ),
        ),
      );
      await settleWithRealIsolate(tester);

      expect(find.textContaining('TARGET_VALUE'), findsOneWidget);
    });

    testWidgets('docked gutter stays pinned when content scrolls horizontally',
        (tester) async {
      final longData = {
        'very_wide_key_that_requires_horizontal_scroll_to_fit':
            'very_wide_value_in_json',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              width: 150,
              child: JsonViewer(data: longData),
            ),
          ),
        ),
      );
      await settleWithRealIsolate(tester);

      final gutterFinder = find.text('1');
      final initialGutterX = tester.getTopLeft(gutterFinder).dx;

      final horizontalScrollable = tester.state<ScrollableState>(
        find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
      );
      horizontalScrollable.position.jumpTo(60.0);
      await settleWithRealIsolate(tester);

      final afterScrollGutterX = tester.getTopLeft(gutterFinder).dx;
      expect(afterScrollGutterX, equals(initialGutterX));
    });

    testWidgets('code folding collapses and expands object entries',
        (tester) async {
      final collData = {
        'section': {
          'sub_1': 'alpha',
          'sub_2': 'beta',
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              width: 400,
              child: JsonViewer(data: collData),
            ),
          ),
        ),
      );
      await settleWithRealIsolate(tester);

      expect(find.textContaining('alpha'), findsOneWidget);

      final foldIcon = find.byIcon(Icons.arrow_drop_down).first;
      await tester.tap(foldIcon);
      await settleWithRealIsolate(tester);

      expect(find.textContaining('alpha'), findsNothing);

      await tester.tap(foldIcon);
      await settleWithRealIsolate(tester);

      expect(find.textContaining('alpha'), findsOneWidget);
    });
  });

  group('Milestone 2: UI Truncation Clean Rendering', () {
    testWidgets(
        'renders response content without warning banner when the response body was preview-truncated',
        (tester) async {
      final largeBytes = Uint8List(5 * 1024 * 1024);
      final record = _createRecord(
          id: 'rec_trunc_banner_1',
          method: 'GET',
          url: 'https://api.example.com/huge_response',
          responseHeaders: {'content-type': 'application/json'},
          responseContentType: 'application/json',
          responseBodyPreview: '{"preview":"first 2MB"}',
          responseSizeBytes: largeBytes.length,
          responseBodyBytes: largeBytes,
          responseTruncation: const BodyTruncation(
            originalBytes: 7000000,
            retainedBytes: 2000000,
            stage: TruncationStage.preview,
          ));
      final entry = _createIndexEntry(record);
      final controller = _MockSessionScopeController(record: record);
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
      await settleWithRealIsolate(tester);

      await tester.tap(find.text('Response'));
      await settleWithRealIsolate(tester);

      expect(find.textContaining('Body truncated preview'), findsNothing);
      expect(find.text('Export Full'), findsNothing);
      expect(find.textContaining('first 2MB'), findsOneWidget);
    });

    testWidgets(
        'does not render warning banner when the response body is complete',
        (tester) async {
      final record = _createRecord(
          id: 'rec_not_trunc_1',
          method: 'GET',
          url: 'https://api.example.com/small_response',
          responseHeaders: {'content-type': 'application/json'},
          responseContentType: 'application/json',
          responseBodyPreview: '{"status":"ok"}',
          responseTruncation: const BodyTruncation.complete(0));
      final entry = _createIndexEntry(record);
      final controller = _MockSessionScopeController(record: record);
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
      await settleWithRealIsolate(tester);

      await tester.tap(find.text('Response'));
      await settleWithRealIsolate(tester);

      expect(find.textContaining('Body truncated preview'), findsNothing);
      expect(find.text('Export Full'), findsNothing);
    });
  });
}

Future<void> settleWithRealIsolate(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (find.byType(CircularProgressIndicator).evaluate().isNotEmpty &&
      DateTime.now().isBefore(deadline)) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(find.byType(CircularProgressIndicator), findsNothing);
  await tester.pumpAndSettle();
}
