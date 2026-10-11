import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/ui/widgets/json_viewer.dart';
import 'package:interceptly/src/export/curl_generator.dart';
import 'package:interceptly/src/export/har_exporter.dart';
import 'package:interceptly/src/export/postman_exporter.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';
import 'package:interceptly/src/model/request_record.dart';

import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/domain_group.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/network_simulation.dart';
import 'package:interceptly/src/model/request_filter.dart';
import 'package:interceptly/src/model/request_summary.dart';
import 'package:interceptly/src/session/inspector_preferences.dart';
import 'package:interceptly/src/session/inspector_session_view.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';

class _FakeSession extends InspectorSessionView {
  _FakeSession({required this.record, required this.entry});

  final RequestRecord record;
  final IndexEntry entry;
  final InspectorPreferences _prefs = InspectorPreferences();

  @override
  InterceptlySettings get settings => const InterceptlySettings();
  @override
  InspectorPreferences get preferences => _prefs;
  @override
  List<RequestSummary> get entries => [entry];
  @override
  RequestFilter get filter => RequestFilter();
  @override
  bool get isEnabled => true;
  @override
  int get droppedCount => 0;
  @override
  NetworkSimulationProfile get networkSimulation =>
      NetworkSimulationProfile.none;
  @override
  String? get masterQuery => null;
  @override
  bool get isMasterSearchActive => false;
  @override
  bool get isScanningBodies => false;
  @override
  bool get isScanningFiles => false;
  @override
  bool get groupingEnabled => false;
  @override
  Future<RequestRecord> loadDetail(RequestSummary summary) async => record;
  @override
  void enable() {}
  @override
  void disable() {}
  @override
  Future<void> clear() async {}
  @override
  void applyFilter(RequestFilter filter) {}
  @override
  void clearFilter() {}
  @override
  void setNetworkSimulation(NetworkSimulationProfile profile) {}
  @override
  void clearNetworkSimulation() {}
  @override
  List<DomainGroup> getGroupedRecords() => const [];
  @override
  void toggleGrouping(bool enabled) {}
  @override
  void toggleDomainExpanded(String domain) {}
  @override
  void cancelMasterSearch() {}
  @override
  Future<void> startMasterSearch(String query) async {}
  @override
  Set<String> get availableDomains => const {};
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
  bool isBodyTruncated = false,
  bool isUiTruncated = false,
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
    isBodyTruncated: isBodyTruncated,
    isUiTruncated: isUiTruncated,
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
    isBodyTruncated: r.isBodyTruncated,
    bodyLocation: BodyLocation.memory,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone 2: Settings and Decoupling Constants', () {
    test('InterceptlySettings defaults decouple storage limit from UI preview limit', () {
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
        isUiTruncated: true,
      );

      expect(record.requestBodyBytes, equals(reqBytes));
      expect(record.responseBodyBytes, equals(resBytes));
      expect(record.isUiTruncated, isTrue);
    });
  });

  group('Milestone 2: Exporter Data Integrity', () {
    test('CurlGenerator prioritizes intact requestBodyBytes over preview string', () {
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

    test('HarExporter utilizes intact requestBodyBytes and responseBodyBytes', () {
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
      final entry = (parsed['log']['entries'] as List).first as Map<String, dynamic>;

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
    testWidgets('renders 5,000 lines cleanly using dual virtualized ListView.builders with itemExtent 18.0', (tester) async {
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
      await tester.pumpAndSettle();

      final listViews = find.byType(ListView);
      expect(listViews, findsNWidgets(2));

      final firstListView = tester.widget<ListView>(listViews.first);
      final secondListView = tester.widget<ListView>(listViews.last);
      expect(firstListView.itemExtent, equals(18.0));
      expect(secondListView.itemExtent, equals(18.0));

      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('navigates to target line on search match jumping', (tester) async {
      final searchData = {
        for (int i = 1; i <= 100; i++) 'item_$i': i == 50 ? 'TARGET_VALUE' : 'val_$i',
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
      await tester.pumpAndSettle();

      expect(find.textContaining('TARGET_VALUE'), findsOneWidget);
    });

    testWidgets('docked gutter stays pinned when content scrolls horizontally', (tester) async {
      final longData = {
        'very_wide_key_that_requires_horizontal_scroll_to_fit': 'very_wide_value_in_json',
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
      await tester.pumpAndSettle();

      final gutterFinder = find.text('1');
      final initialGutterX = tester.getTopLeft(gutterFinder).dx;

      final horizontalScrollable = tester.state<ScrollableState>(
        find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
      );
      horizontalScrollable.position.jumpTo(60.0);
      await tester.pumpAndSettle();

      final afterScrollGutterX = tester.getTopLeft(gutterFinder).dx;
      expect(afterScrollGutterX, equals(initialGutterX));
    });

    testWidgets('code folding collapses and expands object entries', (tester) async {
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
      await tester.pumpAndSettle();

      expect(find.textContaining('alpha'), findsOneWidget);

      final foldIcon = find.byIcon(Icons.arrow_drop_down).first;
      await tester.tap(foldIcon);
      await tester.pumpAndSettle();

      expect(find.textContaining('alpha'), findsNothing);

      await tester.tap(foldIcon);
      await tester.pumpAndSettle();

      expect(find.textContaining('alpha'), findsOneWidget);
    });
  });

  group('Milestone 2: UI Truncation Clean Rendering', () {
    testWidgets('renders response content without warning banner when isUiTruncated is true', (tester) async {
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
        isUiTruncated: true,
      );
      final entry = _createIndexEntry(record);
      final session = _FakeSession(record: record, entry: entry);

      await tester.pumpWidget(
        MaterialApp(
          home: RequestDetailPage(
            entry: entry,
            session: session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Response'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Body truncated preview'), findsNothing);
      expect(find.text('Export Full'), findsNothing);
      expect(find.textContaining('first 2MB'), findsOneWidget);
    });

    testWidgets('does not render warning banner when isUiTruncated is false', (tester) async {
      final record = _createRecord(
        id: 'rec_not_trunc_1',
        method: 'GET',
        url: 'https://api.example.com/small_response',
        responseHeaders: {'content-type': 'application/json'},
        responseContentType: 'application/json',
        responseBodyPreview: '{"status":"ok"}',
        isUiTruncated: false,
      );
      final entry = _createIndexEntry(record);
      final session = _FakeSession(record: record, entry: entry);

      await tester.pumpWidget(
        MaterialApp(
          home: RequestDetailPage(
            entry: entry,
            session: session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Response'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Body truncated preview'), findsNothing);
      expect(find.text('Export Full'), findsNothing);
    });
  });
}
