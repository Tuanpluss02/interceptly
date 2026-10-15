import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/model/domain_group.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/session/inspector_preferences.dart';
import 'package:interceptly/src/ui/detail/detail_search.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';

IndexEntry _createEntry(
  String id, {
  String method = 'GET',
  String url = 'https://api.example.com/items',
  int statusCode = 200,
  int durationMs = 25,
  int requestSizeBytes = 100,
  int responseSizeBytes = 200,
  BodyTruncation responseTruncation = const BodyTruncation.complete(0),
  DateTime? timestamp,
}) {
  return IndexEntry(
    id: id,
    method: method,
    url: '$url/$id',
    statusCode: statusCode,
    durationMs: durationMs,
    requestSizeBytes: requestSizeBytes,
    responseSizeBytes: responseSizeBytes,
    timestamp: timestamp ?? DateTime(2026, 1, 1),
    hasError: statusCode >= 400 || statusCode == 0,
    requestTruncation: const BodyTruncation.complete(0),
    responseTruncation: responseTruncation,
    bodyLocation: BodyLocation.memory,
  );
}

class _MockDetailSession extends InspectorSessionView {
  _MockDetailSession({
    required this.record,
    required this.entry,
  });

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Search goto match counting & synchronization', () {
    test(
        'JsonViewer.countMatches searches string scalars and keys matching _flatten',
        () {
      final data = {
        'targetKey': 'simpleValue',
        'anotherKey': 'contains targetKey here',
      };
      final count = JsonViewer.countMatches(data, 'targetKey');
      expect(count, 2);
    });

    test('All DetailSections have unique values and correct tab mapping', () {
      final record = RequestRecord(
        id: 'rec_1',
        method: 'POST',
        url: 'https://api.example.com/items?query=findme',
        statusCode: 500,
        durationMs: 42,
        requestSizeBytes: 1024,
        responseSizeBytes: 2048,
        timestamp: DateTime(2026, 1, 1),
        requestHeaders: const {'x-request-key': 'req_val'},
        responseHeaders: const {'x-response-key': 'res_val'},
        requestContentType: 'application/json',
        responseContentType: 'application/json',
        requestBodyPreview: '{"name":"findme"}',
        responseBodyPreview: '{"result":"findme"}',
        errorType: 'CrashError',
        errorMessage: 'Fatal findme',
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation(
          originalBytes: 7000000,
          retainedBytes: 5000000,
          stage: TruncationStage.storage,
        ),
      );

      final matches =
          computeMatches(record, 'findme', false, (s) => jsonDecode(s!));
      expect(matches, isNotEmpty);

      for (final m in matches) {
        switch (m.section) {
          case DetailSection.overviewUrl:
          case DetailSection.overviewMethod:
          case DetailSection.overviewStatus:
          case DetailSection.overviewDuration:
          case DetailSection.overviewRequestSize:
          case DetailSection.overviewResponseSize:
          case DetailSection.overviewError:
          case DetailSection.overviewTime:
          case DetailSection.overviewNote:
            expect(m.tabIndex, 0);
            break;
          case DetailSection.queryParams:
          case DetailSection.requestHeaders:
          case DetailSection.requestBody:
            expect(m.tabIndex, 1);
            break;
          case DetailSection.responseHeaders:
          case DetailSection.responseBody:
            expect(m.tabIndex, 2);
            break;
          case DetailSection.errorSummary:
          case DetailSection.errorType:
          case DetailSection.errorMessage:
            expect(m.tabIndex, 3);
            break;
        }
      }
    });

    test('Overview tab error and Error tab summary have distinct sections', () {
      final record = RequestRecord(
        id: 'rec_err',
        method: 'GET',
        url: 'https://api.example.com/fail',
        statusCode: 500,
        durationMs: 10,
        requestSizeBytes: 50,
        responseSizeBytes: 0,
        timestamp: DateTime(2026, 1, 1),
        requestHeaders: const {},
        responseHeaders: const {},
        errorType: 'TimeoutException',
        errorMessage: 'Connection timed out',
      );

      final matches = computeMatches(record, 'Timed out', false, (s) => null);
      final overviewMatches = matches.where((m) => m.tabIndex == 0).toList();
      final errorMatches = matches.where((m) => m.tabIndex == 3).toList();

      expect(overviewMatches, isNotEmpty);
      expect(overviewMatches.first.section, DetailSection.overviewError);

      expect(errorMatches, isNotEmpty);
      expect(
        errorMatches.any((m) =>
            m.section == DetailSection.errorSummary ||
            m.section == DetailSection.errorMessage),
        isTrue,
      );
    });
  });

  group('RequestDetailPage search navigation and scrolling', () {
    testWidgets(
        'Search navigates to response tab and Next/Prev matches cycle cleanly',
        (tester) async {
      final entry = _createEntry('test_scroll_1');

      final headers = <String, String>{};
      for (int i = 0; i < 20; i++) {
        headers['x-header-$i'] = 'value-$i';
      }

      final record = RequestRecord(
        id: 'test_scroll_1',
        method: 'GET',
        url: 'https://api.example.com/items/test_scroll_1',
        statusCode: 200,
        durationMs: 50,
        requestSizeBytes: 100,
        responseSizeBytes: 500,
        timestamp: DateTime(2026, 1, 1),
        requestHeaders: headers,
        responseHeaders: headers,
        requestContentType: 'application/json',
        responseContentType: 'application/json',
        requestBodyPreview: '{"client":"apple"}',
        responseBodyPreview:
            '{"nested":{"deep_target":"secret_scroll_target"}}',
      );

      final session = _MockDetailSession(record: record, entry: entry);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestDetailPage(entry: entry, session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('URL'), findsOneWidget);

      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'secret_scroll_target');
      tester
          .widget<TextField>(searchField)
          .onSubmitted
          ?.call('secret_scroll_target');

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      });
      await tester.pumpAndSettle();

      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.text('RESPONSE BODY'), findsOneWidget);

      final nextButton = find.byTooltip('Next match');
      expect(nextButton, findsOneWidget);
      await tester.tap(nextButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final prevButton = find.byTooltip('Previous match');
      expect(prevButton, findsOneWidget);
      await tester.tap(prevButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'JsonViewer scrolls to activeGlobalIndex without infinite animation loop',
        (tester) async {
      final largeData = <String, dynamic>{
        for (int i = 0; i < 50; i++) 'key_$i': 'value_$i',
        'target_item': 'highlight_me',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: JsonViewer(
                data: largeData,
                searchQuery: 'highlight_me',
                matchOffset: 0,
                activeGlobalIndex: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(JsonViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'JsonViewer scrolls horizontally to bring active match into view for wide text',
        (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final prefix = 'a' * 500;
      final wideData = <String, dynamic>{
        'wideField': '$prefix TARGET_MATCH ${"b" * 500}',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: JsonViewer(
                data: wideData,
                searchQuery: 'TARGET_MATCH',
                matchOffset: 0,
                activeGlobalIndex: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final jsonViewerFinder = find.byType(JsonViewer);
      expect(jsonViewerFinder, findsOneWidget);
      final jvState = tester.state(jsonViewerFinder) as dynamic;
      final hController =
          jvState.horizontalScrollControllerForTest as ScrollController;

      expect(hController.offset, greaterThan(0.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'RequestDetailPage wide-text payload auto-scrolls horizontally and vertically when navigating matches',
        (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const sample = 'The quick brown fox jumps over the lazy dog. 1234567890 ';
      final bigText = sample * 50;

      final bodyJson = jsonEncode({
        'title': 'Wide Text Payload',
        'sampleData': bigText,
      });

      final entry = _createEntry(
        'wide_1',
        url: 'https://api.example.com/api/wide-text',
      );

      final record = RequestRecord(
        id: 'wide_1',
        method: 'GET',
        url: 'https://api.example.com/api/wide-text',
        statusCode: 200,
        durationMs: 30,
        requestSizeBytes: 0,
        responseSizeBytes: utf8.encode(bodyJson).length,
        timestamp: DateTime(2026, 1, 1),
        requestHeaders: const {},
        responseHeaders: const {'content-type': 'application/json'},
        responseContentType: 'application/json',
        responseBodyPreview: bodyJson,
      );

      final session = _MockDetailSession(record: record, entry: entry);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestDetailPage(entry: entry, session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'lazy');
      tester.widget<TextField>(searchField).onSubmitted?.call('lazy');

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      });
      await tester.pumpAndSettle();

      final jsonViewerFinder = find.byType(JsonViewer).last;
      expect(jsonViewerFinder, findsOneWidget);
      final jvState = tester.state(jsonViewerFinder) as dynamic;
      final hController =
          jvState.horizontalScrollControllerForTest as ScrollController;

      final nextButton = find.byTooltip('Next match');
      final prevButton = find.byTooltip('Previous match');

      for (int i = 0; i < 3; i++) {
        await tester.tap(nextButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
      }

      expect(hController.hasClients, isTrue);

      await tester.tap(prevButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'initialQuery pre-populates search and automatically navigates to match',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final entry = _createEntry('req_init_q');
      final record = RequestRecord(
        id: entry.id,
        method: entry.method,
        url: entry.url,
        statusCode: entry.statusCode,
        timestamp: entry.timestamp,
        durationMs: entry.durationMs,
        requestSizeBytes: entry.requestSizeBytes,
        responseSizeBytes: entry.responseSizeBytes,
        requestHeaders: const {'Accept': 'application/json'},
        responseHeaders: const {'Content-Type': 'application/json'},
        responseBodyPreview: '{"secret_key": "initial_target_value"}',
      );

      final session = _MockDetailSession(record: record, entry: entry);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestDetailPage(
              entry: entry,
              session: session,
              initialQuery: 'initial_target',
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      });
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      expect(tester.widget<TextField>(searchField).controller?.text,
          'initial_target');

      expect(find.textContaining('/'), findsWidgets);
    });

    testWidgets(
        'search match -> scroll away -> switch tab -> goto returns and scrolls to match',
        (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final entry = _createEntry('req_repro');
      final payload = <String, dynamic>{
        for (int i = 0; i < 40; i++) 'key_$i': 'value_$i',
        'target_secret': 'found_me_here',
        for (int i = 41; i < 60; i++) 'key_$i': 'value_$i',
      };
      final bodyJson = jsonEncode(payload);

      final record = RequestRecord(
        id: entry.id,
        method: entry.method,
        url: entry.url,
        statusCode: entry.statusCode,
        timestamp: entry.timestamp,
        durationMs: entry.durationMs,
        requestSizeBytes: entry.requestSizeBytes,
        responseSizeBytes: bodyJson.length,
        requestHeaders: const {},
        responseHeaders: const {'content-type': 'application/json'},
        responseContentType: 'application/json',
        responseBodyPreview: bodyJson,
      );

      final session = _MockDetailSession(record: record, entry: entry);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestDetailPage(entry: entry, session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'found_me_here');
      tester.widget<TextField>(searchField).onSubmitted?.call('found_me_here');

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      });
      await tester.pumpAndSettle();

      final jsonViewerFinder = find.byType(JsonViewer).last;
      expect(jsonViewerFinder, findsOneWidget);
      final jvState = tester.state(jsonViewerFinder) as dynamic;
      final contentScroll =
          jvState.contentScrollControllerForTest as ScrollController;

      final matchOffset = contentScroll.offset;
      expect(matchOffset, greaterThan(0.0));

      contentScroll.jumpTo(0.0);
      await tester.pumpAndSettle();
      expect(contentScroll.offset, 0.0);

      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();

      final nextButton = find.byTooltip('Next match');
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      expect(contentScroll.offset, closeTo(matchOffset, 5.0));
    });

    testWidgets(
        'outer ListView: search match in bottom section -> scroll away -> switch tab -> goto returns and scrolls to section',
        (tester) async {
      tester.view.physicalSize = const Size(400, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final entry = _createEntry('req_outer');
      final headers = <String, String>{
        for (int i = 0; i < 30; i++) 'header-$i': 'value-$i',
      };
      final record = RequestRecord(
        id: entry.id,
        method: entry.method,
        url: entry.url,
        statusCode: entry.statusCode,
        timestamp: entry.timestamp,
        durationMs: entry.durationMs,
        requestSizeBytes: entry.requestSizeBytes,
        responseSizeBytes: 100,
        requestHeaders: headers,
        responseHeaders: const {},
        requestContentType: 'application/json',
        requestBodyPreview: '{"needle": "find_in_request_body"}',
      );

      final session = _MockDetailSession(record: record, entry: entry);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestDetailPage(entry: entry, session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'find_in_request_body');
      tester
          .widget<TextField>(searchField)
          .onSubmitted
          ?.call('find_in_request_body');

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      });
      await tester.pumpAndSettle();

      final listViewFinder = find.ancestor(
        of: find.text('REQUEST BODY'),
        matching: find.byType(ListView),
      );
      expect(listViewFinder, findsOneWidget);
      final scrollableState = tester.state<ScrollableState>(
        find.ancestor(
          of: find.text('REQUEST BODY'),
          matching: find.byType(Scrollable),
        ),
      );
      final initialOffset = scrollableState.position.pixels;
      expect(initialOffset, greaterThan(0.0));

      scrollableState.position.jumpTo(0.0);
      await tester.pumpAndSettle();
      expect(scrollableState.position.pixels, 0.0);

      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();

      final nextButton = find.byTooltip('Next match');
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      expect(scrollableState.position.pixels, greaterThan(0.0));
      expect(find.text('REQUEST BODY'), findsOneWidget);
    });

    testWidgets(
        'tap match counter capsule on another tab returns and scrolls to match',
        (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final entry = _createEntry('req_pill_tap');
      final payload = <String, dynamic>{
        for (int i = 0; i < 40; i++) 'key_$i': 'value_$i',
        'target_secret': 'pill_target_value',
        for (int i = 41; i < 60; i++) 'key_$i': 'value_$i',
      };
      final bodyJson = jsonEncode(payload);

      final record = RequestRecord(
        id: entry.id,
        method: entry.method,
        url: entry.url,
        statusCode: entry.statusCode,
        timestamp: entry.timestamp,
        durationMs: entry.durationMs,
        requestSizeBytes: entry.requestSizeBytes,
        responseSizeBytes: bodyJson.length,
        requestHeaders: const {},
        responseHeaders: const {'content-type': 'application/json'},
        responseContentType: 'application/json',
        responseBodyPreview: bodyJson,
      );

      final session = _MockDetailSession(record: record, entry: entry);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestDetailPage(entry: entry, session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'pill_target_value');
      tester
          .widget<TextField>(searchField)
          .onSubmitted
          ?.call('pill_target_value');

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      });
      await tester.pumpAndSettle();

      final jsonViewerFinder = find.byType(JsonViewer).last;
      final jvState = tester.state(jsonViewerFinder) as dynamic;
      final contentScroll =
          jvState.contentScrollControllerForTest as ScrollController;

      final matchOffset = contentScroll.offset;
      expect(matchOffset, greaterThan(0.0));

      contentScroll.jumpTo(0.0);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();

      final pillFinder = find.byTooltip('Go to current match');
      expect(pillFinder, findsOneWidget);
      await tester.tap(pillFinder);
      await tester.pumpAndSettle();

      expect(contentScroll.offset, closeTo(matchOffset, 5.0));
    });

    testWidgets(
        'same tab: scroll away inside JsonViewer -> tap next match scrolls back to match',
        (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final entry = _createEntry('req_same_tab');
      final payload = <String, dynamic>{
        for (int i = 0; i < 40; i++) 'key_$i': 'value_$i',
        'target_secret': 'same_tab_target',
        for (int i = 41; i < 60; i++) 'key_$i': 'value_$i',
      };
      final bodyJson = jsonEncode(payload);

      final record = RequestRecord(
        id: entry.id,
        method: entry.method,
        url: entry.url,
        statusCode: entry.statusCode,
        timestamp: entry.timestamp,
        durationMs: entry.durationMs,
        requestSizeBytes: entry.requestSizeBytes,
        responseSizeBytes: bodyJson.length,
        requestHeaders: const {},
        responseHeaders: const {'content-type': 'application/json'},
        responseContentType: 'application/json',
        responseBodyPreview: bodyJson,
      );

      final session = _MockDetailSession(record: record, entry: entry);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestDetailPage(entry: entry, session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'same_tab_target');
      tester
          .widget<TextField>(searchField)
          .onSubmitted
          ?.call('same_tab_target');

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      });
      await tester.pumpAndSettle();

      final jsonViewerFinder = find.byType(JsonViewer).last;
      final jvState = tester.state(jsonViewerFinder) as dynamic;
      final contentScroll =
          jvState.contentScrollControllerForTest as ScrollController;

      final matchOffset = contentScroll.offset;
      expect(matchOffset, greaterThan(0.0));

      contentScroll.jumpTo(0.0);
      await tester.pumpAndSettle();
      expect(contentScroll.offset, 0.0);

      final nextButton = find.byTooltip('Next match');
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      expect(contentScroll.offset, closeTo(matchOffset, 5.0));
    });
  });
}
