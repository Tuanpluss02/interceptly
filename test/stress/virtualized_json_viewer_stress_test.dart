import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interceptly/src/export/curl_generator.dart';
import 'package:interceptly/src/export/har_exporter.dart';
import 'package:interceptly/src/export/postman_exporter.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/domain_group.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';
import 'package:interceptly/src/model/network_simulation.dart';
import 'package:interceptly/src/model/raw_capture.dart';
import 'package:interceptly/src/model/request_filter.dart';
import 'package:interceptly/src/model/request_record.dart';
import 'package:interceptly/src/model/request_summary.dart';
import 'package:interceptly/src/session/inspector_preferences.dart';
import 'package:interceptly/src/session/inspector_session.dart';
import 'package:interceptly/src/session/inspector_session_view.dart';
import 'package:interceptly/src/ui/detail/replay_handler.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';
import 'package:interceptly/src/ui/widgets/json_viewer.dart';

class _MockSessionView extends InspectorSessionView {
  _MockSessionView({required this.record, required this.entry});
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

  late Directory globalTempDir;

  setUp(() async {
    globalTempDir =
        await Directory.systemTemp.createTemp('interceptly_challenger_m2_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') return globalTempDir.path;
        return null;
      },
    );
  });

  tearDown(() async {
    try {
      await globalTempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Empirical Challenge 1: Virtualized JsonViewer Stress & Performance',
      () {
    testWidgets(
        'renders 20,000 lines without freezing, verifying true virtualization',
        (tester) async {
      final massiveMap = <String, dynamic>{
        for (int i = 1; i <= 20000; i++) 'row_$i': 'value_content_$i',
      };

      final stopwatch = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 360,
              width: 500,
              child: JsonViewer(data: massiveMap),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(1500));

      // Virtualization verification: row 1 is rendered, row 15000 is offscreen and unmounted
      expect(find.textContaining('"row_1":'), findsOneWidget);
      expect(find.textContaining('"row_15000":'), findsNothing);

      // Verify dual ListView.builder itemExtent
      final listViews = find.byType(ListView);
      expect(listViews, findsNWidgets(2));
      for (final lv in listViews.evaluate()) {
        final widget = lv.widget as ListView;
        expect(widget.itemExtent, equals(18.0));
      }
    });

    testWidgets(
        'stress tests aggressive scrolling and verified dual-scroll synchronization',
        (tester) async {
      final dataset = <String, dynamic>{
        for (int i = 1; i <= 5000; i++) 'k_$i': 'v_$i',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              width: 400,
              child: JsonViewer(data: dataset),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final listViews = find.byType(ListView);
      final gutterList = listViews.first;
      final contentList = listViews.last;

      final gutterScrollState = tester.state<ScrollableState>(
        find.descendant(of: gutterList, matching: find.byType(Scrollable)),
      );
      final contentScrollState = tester.state<ScrollableState>(
        find.descendant(of: contentList, matching: find.byType(Scrollable)),
      );

      // Scroll content down by 1800 px (100 lines)
      contentScrollState.position.jumpTo(1800.0);
      await tester.pumpAndSettle();

      expect(
        (gutterScrollState.position.pixels - contentScrollState.position.pixels)
            .abs(),
        lessThan(0.01),
      );

      // Scroll gutter down further by 3600 px (another 200 lines)
      gutterScrollState.position.jumpTo(5400.0);
      await tester.pumpAndSettle();

      expect(
        (contentScrollState.position.pixels - gutterScrollState.position.pixels)
            .abs(),
        lessThan(0.01),
      );
    });

    testWidgets(
        'stress tests deep nesting up to 40 levels without stack overflow',
        (tester) async {
      dynamic nested = 'leaf_reached_at_level_40';
      for (int i = 40; i >= 1; i--) {
        nested = {'level_$i': nested};
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              width: 400,
              child: JsonViewer(data: nested),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('"level_1":'), findsOneWidget);
    });

    testWidgets(
        'search jumping accurately centers match at line 3500 and auto-expands ancestors',
        (tester) async {
      final searchData = <String, dynamic>{
        for (int i = 1; i <= 5000; i++)
          'entry_$i':
              i == 3500 ? {'hidden_sub': 'SEARCH_PINPOINT_TARGET'} : 'val_$i',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 360,
              width: 500,
              child: JsonViewer(
                data: searchData,
                searchQuery: 'SEARCH_PINPOINT_TARGET',
                activeGlobalIndex: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('SEARCH_PINPOINT_TARGET'), findsOneWidget);

      final listViews = find.byType(ListView);
      final contentList = listViews.last;
      final contentScrollState = tester.state<ScrollableState>(
        find.descendant(of: contentList, matching: find.byType(Scrollable)),
      );

      expect(contentScrollState.position.pixels, greaterThan(60000.0));
    });

    testWidgets('multi-match jump sequence updates scroll position accurately',
        (tester) async {
      final multiMatchData = <String, dynamic>{
        for (int i = 1; i <= 3000; i++)
          'item_$i': (i == 100 || i == 1500 || i == 2800)
              ? 'MATCH_OCCURRENCE'
              : 'filler_$i',
      };

      // Jump to match 0 (around line 100)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              width: 400,
              child: JsonViewer(
                data: multiMatchData,
                searchQuery: 'MATCH_OCCURRENCE',
                activeGlobalIndex: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final listViews = find.byType(ListView);
      final contentList = listViews.last;
      var scrollState = tester.state<ScrollableState>(
        find.descendant(of: contentList, matching: find.byType(Scrollable)),
      );
      final offsetMatch0 = scrollState.position.pixels;
      expect(offsetMatch0, lessThan(3000.0));

      // Jump to match 1 (around line 1500)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              width: 400,
              child: JsonViewer(
                data: multiMatchData,
                searchQuery: 'MATCH_OCCURRENCE',
                activeGlobalIndex: 1,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      scrollState = tester.state<ScrollableState>(
        find.descendant(of: contentList, matching: find.byType(Scrollable)),
      );
      final offsetMatch1 = scrollState.position.pixels;
      expect(offsetMatch1, greaterThan(24000.0));
      expect(offsetMatch1, greaterThan(offsetMatch0));

      // Jump to match 2 (around line 2800)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              width: 400,
              child: JsonViewer(
                data: multiMatchData,
                searchQuery: 'MATCH_OCCURRENCE',
                activeGlobalIndex: 2,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      scrollState = tester.state<ScrollableState>(
        find.descendant(of: contentList, matching: find.byType(Scrollable)),
      );
      final offsetMatch2 = scrollState.position.pixels;
      expect(offsetMatch2, greaterThan(45000.0));
      expect(offsetMatch2, greaterThan(offsetMatch1));
    });
  });

  group(
      'Empirical Challenge 2: Large Payload Storage & Truncation Decoupling (>2MB up to 50MB)',
      () {
    test(
        '3 MB payload (>2MB UI limit) is stored 100% intact to disk; UI preview is cleanly sliced to 2MB',
        () async {
      final session = InspectorSession(
        settings: const InterceptlySettings(
          bodyOffloadThreshold: 10 * 1024,
          maxBodyBytes: 50 * 1024 * 1024,
          maxUiPreviewBytes: 2 * 1024 * 1024,
        ),
      );
      await session.initialize();

      final prefix = '{"head":"start", "data":"';
      final suffix = '", "tail":"REACHED_END_OF_3MB"}';
      final middleLen = 3 * 1024 * 1024 - prefix.length - suffix.length;
      final payloadText = '$prefix${'A' * middleLen}$suffix';
      final payloadBytes = Uint8List.fromList(utf8.encode(payloadText));
      expect(payloadBytes.length, equals(3 * 1024 * 1024));

      final capture = RawCapture(
        id: 'cap_3mb',
        method: 'POST',
        url: 'https://api.example.com/large3mb',
        statusCode: 200,
        timestamp: DateTime.now(),
        durationMs: 120,
        requestHeaders: {'content-type': 'application/json'},
        responseHeaders: {'content-type': 'application/json'},
        requestContentType: 'application/json',
        responseContentType: 'application/json',
        requestBodyBytes: RawCapture.wrapBytes(payloadBytes),
        responseBodyBytes: RawCapture.wrapBytes(payloadBytes),
      );

      session.record(capture);

      final end = DateTime.now().add(const Duration(seconds: 10));
      while (session.entries.isEmpty) {
        if (DateTime.now().isAfter(end)) {
          throw StateError('timeout waiting for cap_3mb entry');
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final entry =
          session.entries.firstWhere((e) => e.id == 'cap_3mb') as IndexEntry;
      expect(entry.bodyLocation, equals(BodyLocation.file));
      expect(entry.isTruncated, isFalse);

      final record = await session.loadDetail(entry);

      expect(record.requestBodyBytes, isNotNull);
      expect(record.requestBodyBytes!.length, equals(3 * 1024 * 1024));
      expect(record.responseBodyBytes, isNotNull);
      expect(record.responseBodyBytes!.length, equals(3 * 1024 * 1024));

      final decodedTail = utf8.decode(record.responseBodyBytes!
          .sublist(record.responseBodyBytes!.length - 40));
      expect(decodedTail, contains('REACHED_END_OF_3MB'));

      expect(record.responseTruncation.isPreviewOnly, isTrue);
      expect(record.responseBodyPreview, isNotNull);
      expect(record.responseBodyPreview!.length,
          lessThanOrEqualTo(2 * 1024 * 1024 + 10));
      expect(record.responseBodyPreview, isNot(contains('REACHED_END_OF_3MB')));

      await session.dispose();
    });

    test(
        'storage ceiling: when maxBodyBytes = 4MB, a 6MB payload is truncated at 4MB reported as preview-truncated',
        () async {
      final session = InspectorSession(
        settings: const InterceptlySettings(
          bodyOffloadThreshold: 10 * 1024,
          maxBodyBytes: 4 * 1024 * 1024,
          maxUiPreviewBytes: 2 * 1024 * 1024,
        ),
      );
      await session.initialize();

      final payloadBytes = Uint8List(6 * 1024 * 1024);
      final capture = RawCapture(
        id: 'cap_6mb',
        method: 'POST',
        url: 'https://api.example.com/cap',
        statusCode: 200,
        timestamp: DateTime.now(),
        durationMs: 150,
        requestHeaders: {'content-type': 'application/octet-stream'},
        responseHeaders: {'content-type': 'application/octet-stream'},
        responseBodyBytes: RawCapture.wrapBytes(payloadBytes),
      );

      session.record(capture);

      final end = DateTime.now().add(const Duration(seconds: 10));
      while (session.entries.isEmpty) {
        if (DateTime.now().isAfter(end)) {
          throw StateError('timeout waiting for cap_6mb entry');
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final entry =
          session.entries.firstWhere((e) => e.id == 'cap_6mb') as IndexEntry;
      expect(entry.responseTruncation.hasDataLoss, isTrue);

      final record = await session.loadDetail(entry);
      expect(record.responseBodyBytes!.length, equals(4 * 1024 * 1024));
      expect(record.responseTruncation.hasDataLoss, isTrue);
      expect(
        record.responseTruncation.stage,
        TruncationStage.storageAndPreview,
        reason: 'storage capped at 4MB and the preview shows even less',
      );
      expect(record.responseTruncation.retainedBytes, 2 * 1024 * 1024);

      await session.dispose();
    });

    test(
        'unlimited storage: when maxBodyBytes <= 0, bodies are preserved without ceiling cap',
        () async {
      final session = InspectorSession(
        settings: const InterceptlySettings(
          bodyOffloadThreshold: 10 * 1024,
          maxBodyBytes: 0,
          maxUiPreviewBytes: 2 * 1024 * 1024,
        ),
      );
      await session.initialize();

      final payloadBytes = Uint8List(5 * 1024 * 1024);
      final capture = RawCapture(
        id: 'cap_unlimited',
        method: 'POST',
        url: 'https://api.example.com/unlimited',
        statusCode: 200,
        timestamp: DateTime.now(),
        durationMs: 100,
        requestHeaders: {'content-type': 'application/octet-stream'},
        responseHeaders: {'content-type': 'application/octet-stream'},
        responseBodyBytes: RawCapture.wrapBytes(payloadBytes),
      );

      session.record(capture);

      final end = DateTime.now().add(const Duration(seconds: 10));
      while (session.entries.isEmpty) {
        if (DateTime.now().isAfter(end)) {
          throw StateError('timeout waiting for cap_unlimited entry');
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final entry = session.entries.firstWhere((e) => e.id == 'cap_unlimited')
          as IndexEntry;
      expect(entry.responseTruncation.stage, TruncationStage.none);

      final record = await session.loadDetail(entry);
      expect(record.responseBodyBytes!.length, equals(5 * 1024 * 1024));
      expect(record.hasDataLoss, isFalse);
      expect(
        record.responseTruncation.stage,
        TruncationStage.preview,
        reason: 'unlimited storage still shows a capped preview',
      );

      await session.dispose();
    });
  });

  group(
      'Empirical Challenge 3: Exporters & Replay Byte Fidelity with Payloads > 2MB',
      () {
    late Directory replayTempDir;
    late InspectorSession replaySession;

    setUp(() async {
      replayTempDir =
          await Directory.systemTemp.createTemp('interceptly_replay_m2_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (call.method == 'getTemporaryDirectory') return replayTempDir.path;
          return null;
        },
      );
      replaySession = InspectorSession();
      await replaySession.initialize();
    });

    tearDown(() async {
      await replaySession.dispose();
      try {
        await replayTempDir.delete(recursive: true);
      } catch (_) {}
    });

    test(
        'CurlGenerator exports full intact 3MB payload, not the truncated 2MB preview',
        () {
      final intact3Mb =
          '{"full_3mb_data":"${'X' * (3 * 1024 * 1024 - 40)}","intact_end":true}';
      final truncatedPreview =
          '{"full_3mb_data":"${'X' * (2 * 1024 * 1024 - 40)}';

      final record = RequestRecord(
          id: 'rec_curl_3mb',
          method: 'POST',
          url: 'https://api.example.com/heavy',
          statusCode: 200,
          timestamp: DateTime.now(),
          durationMs: 45,
          requestHeaders: {'content-type': 'application/json'},
          responseHeaders: {},
          requestBodyPreview: truncatedPreview,
          requestBodyBytes: Uint8List.fromList(utf8.encode(intact3Mb)),
          requestSizeBytes: intact3Mb.length,
          responseSizeBytes: 0,
          responseTruncation: const BodyTruncation(
            originalBytes: 7000000,
            retainedBytes: 2000000,
            stage: TruncationStage.preview,
          ));

      final curl = CurlGenerator.fromRecord(record);
      expect(curl, contains('intact_end'));
      expect(curl.length, greaterThan(3 * 1024 * 1024));
    });

    test('HarExporter and PostmanExporter preserve full intact 3MB payloads',
        () {
      final intact3Mb =
          '{"export_payload":"${'Y' * (3 * 1024 * 1024 - 40)}","end_marker":99}';
      final truncatedPreview =
          '{"export_payload":"${'Y' * (2 * 1024 * 1024 - 40)}';

      final record = RequestRecord(
          id: 'rec_export_3mb',
          method: 'POST',
          url: 'https://api.example.com/export_test',
          statusCode: 200,
          timestamp: DateTime.now(),
          durationMs: 50,
          requestHeaders: {'content-type': 'application/json'},
          responseHeaders: {'content-type': 'application/json'},
          requestBodyPreview: truncatedPreview,
          responseBodyPreview: truncatedPreview,
          requestBodyBytes: Uint8List.fromList(utf8.encode(intact3Mb)),
          responseBodyBytes: Uint8List.fromList(utf8.encode(intact3Mb)),
          requestSizeBytes: intact3Mb.length,
          responseSizeBytes: intact3Mb.length,
          responseTruncation: const BodyTruncation(
            originalBytes: 7000000,
            retainedBytes: 2000000,
            stage: TruncationStage.preview,
          ));

      final harJson = HarExporter.toJson([record]);
      expect(harJson, contains('end_marker'));

      final postmanJson = PostmanExporter.toJson([record]);
      expect(postmanJson, contains('end_marker'));
    });

    testWidgets(
        'ReplayHandler re-sends full 3MB intact bytes over network on retry',
        (tester) async {
      final intact3Mb =
          '{"replay_action":"send","content":"${'Z' * (3 * 1024 * 1024 - 50)}","final":true}';
      final truncatedPreview =
          '{"replay_action":"send","content":"${'Z' * (2 * 1024 * 1024 - 50)}';
      final intactBytes = Uint8List.fromList(utf8.encode(intact3Mb));

      final record = RequestRecord(
          id: 'rec_replay_3mb',
          method: 'POST',
          url: 'https://api.example.com/replay_heavy',
          statusCode: 200,
          timestamp: DateTime.now(),
          durationMs: 30,
          requestHeaders: {'content-type': 'application/json'},
          responseHeaders: {},
          requestBodyPreview: truncatedPreview,
          requestBodyBytes: intactBytes,
          requestSizeBytes: intactBytes.length,
          responseSizeBytes: 0,
          responseTruncation: const BodyTruncation(
            originalBytes: 7000000,
            retainedBytes: 2000000,
            stage: TruncationStage.preview,
          ));

      http.Request? capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response('{"replayed": true}', 200);
      });

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

      await tester.runAsync(() async {
        await http.runWithClient(() async {
          final handler =
              ReplayHandler(context: savedContext, session: replaySession);
          await handler.retry(record);
        }, () => mockClient);
      });

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.bodyBytes.length, equals(intactBytes.length));
      final decodedBody = utf8.decode(capturedRequest!.bodyBytes);
      expect(decodedBody, contains('"final":true'));
    });
  });

  group('Empirical Challenge 4: UI Truncation Clean Rendering', () {
    testWidgets(
        'Response tab renders response cleanly without warning banner when the response body was preview-truncated',
        (tester) async {
      final largeBytes = Uint8List(4 * 1024 * 1024);
      final record = RequestRecord(
          id: 'rec_ui_banner_check',
          method: 'GET',
          url: 'https://api.example.com/download_data',
          statusCode: 200,
          timestamp: DateTime.now(),
          durationMs: 80,
          requestHeaders: {},
          responseHeaders: {'content-type': 'application/json'},
          responseContentType: 'application/json',
          responseBodyPreview: '{"preview_content": "first 2MB"}',
          responseBodyBytes: largeBytes,
          requestSizeBytes: 0,
          responseSizeBytes: largeBytes.length,
          responseTruncation: const BodyTruncation(
            originalBytes: 7000000,
            retainedBytes: 2000000,
            stage: TruncationStage.preview,
          ));
      final entry = IndexEntry(
        id: record.id,
        method: record.method,
        url: record.url,
        statusCode: record.statusCode,
        durationMs: record.durationMs,
        requestSizeBytes: 0,
        responseSizeBytes: record.responseSizeBytes,
        timestamp: record.timestamp,
        hasError: false,
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation.complete(0),
        bodyLocation: BodyLocation.memory,
      );
      final session = _MockSessionView(record: record, entry: entry);

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
  });
}
