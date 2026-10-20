// ignore_for_file: invalid_use_of_internal_member
@Tags(['stress'])
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/engine/memory_index.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';

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

class _MockDetailScopeController extends InterceptlyScopeController {
  _MockDetailScopeController({required this.record, InterceptlyEngine? engine})
      : super(engine: engine ?? InterceptlyEngine.instance);

  final RequestRecord record;

  @override
  Future<RequestRecord> loadDetail(RequestSummary summary) async => record;

  @override
  Future<RequestRecord> loadDetailById(String id) async => record;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('challenger_m1_instance2');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      },
    );
  });

  tearDownAll(() async {
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Adversarial Group 1: MemoryIndex Boundary maxEntries = 0 and Negative',
      () {
    test('maxEntries = 0: initial properties, accessors, and clamp on add', () {
      final index = MemoryIndex(maxEntries: 0);

      expect(index.length, 0);
      expect(index.entries, isEmpty);
      expect(index.byId('missing'), isNull);
      expect(index.filtered(RequestFilter()), isEmpty);

      expect(() => index.clear(), returnsNormally);
      expect(index.length, 0);
      expect(index.entries, isEmpty);

      expect(() => index.add(_createEntry('e1')), returnsNormally);
      expect(index.length, 1);
      expect(index.entries.single.id, 'e1');
    });

    test('maxEntries < 0: initial properties and clamp on add', () {
      for (final cap in [-1, -5, -999]) {
        final index = MemoryIndex(maxEntries: cap);
        expect(index.length, 0);
        expect(index.entries, isEmpty);
        expect(index.byId('any'), isNull);
        expect(() => index.clear(), returnsNormally);
        expect(() => index.add(_createEntry('neg')), returnsNormally);
        expect(index.length, 1);
        expect(index.entries.single.id, 'neg');
      }
    });

    test('Unmodifiable list view properties on empty/zero MemoryIndex', () {
      final index = MemoryIndex(maxEntries: 0);
      final list = index.entries;

      expect(() => list.add(_createEntry('x')), throwsUnsupportedError);
      expect(() => list.clear(), throwsUnsupportedError);
      expect(() => list.removeAt(0), throwsUnsupportedError);
      expect(() => list[0], throwsA(isA<RangeError>()));
    });
  });

  group('Adversarial Group 2: MemoryIndex Boundary maxEntries = 1', () {
    test(
        'maxEntries = 1: single slot lifecycle across 5,000 rapid churn operations',
        () {
      final index = MemoryIndex(maxEntries: 1);
      expect(index.length, 0);
      expect(index.entries, isEmpty);

      for (var i = 0; i < 5000; i++) {
        final id = 'req_$i';
        final initial = _createEntry(id, statusCode: 0);
        index.add(initial);

        expect(index.length, 1);
        expect(index.entries.length, 1);
        expect(index.entries[0].id, id);
        expect(index.entries[0].statusCode, 0);
        expect(index.byId(id)?.statusCode, 0);

        if (i > 0) {
          final prevId = 'req_${i - 1}';
          expect(index.byId(prevId), isNull);
        }

        final updated = _createEntry(id, statusCode: 200, durationMs: i);
        index.add(updated);

        expect(index.length, 1);
        expect(index.entries.length, 1);
        expect(index.entries[0].id, id);
        expect(index.entries[0].statusCode, 200);
        expect(index.entries[0].durationMs, i);
        expect(index.byId(id)?.durationMs, i);
      }
    });

    test('maxEntries = 1: Rapid clear and refill cycle', () {
      final index = MemoryIndex(maxEntries: 1);

      for (var round = 0; round < 200; round++) {
        index.add(_createEntry('r_$round'));
        expect(index.length, 1);
        expect(index.byId('r_$round'), isNotNull);

        index.clear();
        expect(index.length, 0);
        expect(index.entries, isEmpty);
        expect(index.byId('r_$round'), isNull);
      }
    });

    test('Stale view behavior: accessing entries view after index.clear()', () {
      final index = MemoryIndex(maxEntries: 5);
      index.add(_createEntry('e1'));
      index.add(_createEntry('e2'));

      final view = index.entries;
      expect(view.length, 2);
      expect(view[0].id, 'e2');
      expect(view[1].id, 'e1');

      index.clear();
      expect(index.length, 0);
      expect(index.entries, isEmpty);

      expect(view.length, 2);
      expect(() => view[0], throwsA(isA<TypeError>()));
    });

    test('maxEntries = 1: Index bounds verification on entries view', () {
      final index = MemoryIndex(maxEntries: 1);
      index.add(_createEntry('solo'));

      final list = index.entries;
      expect(list.length, 1);
      expect(list[0].id, 'solo');

      expect(() => list[-1], throwsA(isA<RangeError>()));
      expect(() => list[1], throwsA(isA<RangeError>()));
      expect(() => list[99], throwsA(isA<RangeError>()));
    });
  });

  group(
      'Adversarial Group 3: MemoryIndex Capacity Overflow, Eviction, & Wrap-Around',
      () {
    test(
        'Multi-cycle ring wrap-around with strict newest-first invariant validation',
        () {
      const capacity = 7;
      final index = MemoryIndex(maxEntries: capacity);

      for (var n = 1; n <= 100; n++) {
        final id = 'item_$n';
        index.add(_createEntry(id));

        final expectedCount = min(n, capacity);
        expect(index.length, expectedCount);
        expect(index.entries.length, expectedCount);

        expect(index.entries.first.id, id);

        for (var k = 0; k < expectedCount; k++) {
          final expectedId = 'item_${n - k}';
          expect(index.entries[k].id, expectedId);
          expect(index.byId(expectedId)?.id, expectedId);
        }

        if (n > capacity) {
          final evictedId = 'item_${n - capacity}';
          expect(index.byId(evictedId), isNull);
        }
      }
    });

    test(
        'In-place update of oldest, newest, and middle entries during wrap-around',
        () {
      const capacity = 5;
      final index = MemoryIndex(maxEntries: capacity);

      for (var i = 1; i <= 5; i++) {
        index.add(_createEntry('item_$i', statusCode: 0));
      }
      expect(index.entries.map((e) => e.id).toList(), [
        'item_5',
        'item_4',
        'item_3',
        'item_2',
        'item_1',
      ]);

      index.add(_createEntry('item_6', statusCode: 0));
      index.add(_createEntry('item_7', statusCode: 0));
      index.add(_createEntry('item_8', statusCode: 0));

      expect(index.entries.map((e) => e.id).toList(), [
        'item_8',
        'item_7',
        'item_6',
        'item_5',
        'item_4',
      ]);

      final updated4 = _createEntry('item_4', statusCode: 200, durationMs: 444);
      index.add(updated4);
      expect(index.length, capacity);
      expect(index.entries[4].id, 'item_4');
      expect(index.entries[4].statusCode, 200);
      expect(index.entries[4].durationMs, 444);
      expect(index.byId('item_4')?.durationMs, 444);
      expect(index.entries.map((e) => e.id).toList(), [
        'item_8',
        'item_7',
        'item_6',
        'item_5',
        'item_4',
      ]);

      final updated8 = _createEntry('item_8', statusCode: 201, durationMs: 888);
      index.add(updated8);
      expect(index.entries[0].id, 'item_8');
      expect(index.entries[0].statusCode, 201);
      expect(index.byId('item_8')?.durationMs, 888);

      final updated6 = _createEntry('item_6', statusCode: 304, durationMs: 666);
      index.add(updated6);
      expect(index.entries[2].id, 'item_6');
      expect(index.entries[2].statusCode, 304);
      expect(index.byId('item_6')?.durationMs, 666);

      index.add(_createEntry('item_9', statusCode: 0));
      expect(index.length, capacity);
      expect(index.byId('item_4'), isNull);
      expect(index.entries.map((e) => e.id).toList(), [
        'item_9',
        'item_8',
        'item_7',
        'item_6',
        'item_5',
      ]);
    });

    test(
        'Filtered query results accurately reflect newest-first ordering and eviction',
        () {
      const capacity = 10;
      final index = MemoryIndex(maxEntries: capacity);

      for (var i = 0; i < 20; i++) {
        index.add(_createEntry(
          'req_$i',
          statusCode: i % 2 == 0 ? 200 : 500,
          url: i % 3 == 0 ? 'https://auth.api.com' : 'https://data.api.com',
        ));
      }

      expect(index.length, capacity);

      final errorFilter = RequestFilter(
        include2xx: false,
        include3xx: false,
        include4xx: false,
        include5xx: true,
      );
      final errorResults = index.filtered(errorFilter);
      for (final r in errorResults) {
        expect(r.statusCode, 500);
      }
      expect(errorResults.map((e) => e.id).toList(), [
        'req_19',
        'req_17',
        'req_15',
        'req_13',
        'req_11',
      ]);

      final domainFilter = RequestFilter(domains: {'auth.api.com'});
      final domainResults = index.filtered(domainFilter);
      for (final r in domainResults) {
        expect(r.url, contains('auth.api.com'));
      }
      expect(domainResults.map((e) => e.id).toList(), [
        'req_18',
        'req_15',
        'req_12',
      ]);
    });
  });

  group('Adversarial Group 4: Concurrent Asynchronous Updates and Lookups', () {
    test(
        'High-contention concurrent async operations (interleaved adds, updates, lookups, clears)',
        () async {
      const capacity = 30;
      final index = MemoryIndex(maxEntries: capacity);
      final random = Random(42);

      var addCount = 0;
      var updateCount = 0;
      var lookupCount = 0;
      var lookupHits = 0;
      var lookupMisses = 0;

      final futures = <Future<void>>[];

      futures.add(Future(() async {
        for (var i = 0; i < 600; i++) {
          final id = 'flow_${i % 150}';
          index.add(_createEntry(id, statusCode: 0, durationMs: i));
          addCount++;
          if (i % 30 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
      }));

      futures.add(Future(() async {
        for (var i = 0; i < 600; i++) {
          final targetId = 'flow_${random.nextInt(150)}';
          final status = random.nextBool() ? 200 : 404;
          index.add(
              _createEntry(targetId, statusCode: status, durationMs: i + 1000));
          updateCount++;
          if (i % 30 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
      }));

      futures.add(Future(() async {
        for (var i = 0; i < 1000; i++) {
          final queryId = 'flow_${random.nextInt(150)}';
          final result = index.byId(queryId);
          lookupCount++;
          if (result != null) {
            lookupHits++;
            expect(result.id, queryId);
          } else {
            lookupMisses++;
          }
          if (i % 50 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
      }));

      futures.add(Future(() async {
        for (var i = 0; i < 200; i++) {
          final len = index.length;
          expect(len, lessThanOrEqualTo(capacity));

          final snapshot = index.entries;
          expect(snapshot.length, len);

          final ids = snapshot.map((e) => e.id).toList();
          final uniqueIds = ids.toSet();
          expect(ids.length, uniqueIds.length,
              reason: 'Found duplicate IDs in entries');

          for (final item in snapshot) {
            final found = index.byId(item.id);
            expect(found, isNotNull);
            expect(found!.id, item.id);
          }

          await Future<void>.delayed(Duration.zero);
        }
      }));

      await Future.wait(futures);

      expect(addCount, 600);
      expect(updateCount, 600);
      expect(lookupCount, 1000);
      expect(lookupHits, greaterThan(0));
      expect(lookupMisses, greaterThanOrEqualTo(0));
      expect(index.length, lessThanOrEqualTo(capacity));
    });
  });

  group(
      'Adversarial Group 5: Detail Page Lazy Tabs during Search Auto-Jump & Rapid Switching',
      () {
    testWidgets(
      'Search auto-jump only mounts target tab and preserves unvisited tabs as unmounted',
      (tester) async {
        final entry = _createEntry('search_jump_1', statusCode: 500);
        final record = RequestRecord(
          id: 'search_jump_1',
          method: 'GET',
          url: 'https://api.example.com/search_jump_1',
          statusCode: 500,
          durationMs: 30,
          requestSizeBytes: 100,
          responseSizeBytes: 200,
          timestamp: DateTime(2026, 1, 1),
          requestHeaders: const {
            'x-request-unique-marker': 'marker_only_in_request_tab',
          },
          responseHeaders: const {
            'x-response-unique-marker': 'marker_only_in_response_tab',
          },
          requestContentType: 'application/json',
          responseContentType: 'application/json',
          requestBodyPreview: '{"req_field":"req_val"}',
          responseBodyPreview: '{"res_secret":"unique_target_word"}',
          errorType: 'ServerCrashError',
          errorMessage: 'critical_failure_token',
        );

        final controller = _MockDetailScopeController(record: record);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InterceptlyScope(
                controller: controller,
                child: RequestDetailPage(entry: entry),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('URL'), findsOneWidget);
        expect(find.text('REQUEST HEADERS', skipOffstage: false), findsNothing);
        expect(
            find.text('RESPONSE HEADERS', skipOffstage: false), findsNothing);
        expect(find.text('ERROR SUMMARY', skipOffstage: false), findsNothing);

        final searchField = find.byType(TextField);
        expect(searchField, findsOneWidget);
        await tester.enterText(searchField, 'unique_target_word');
        tester
            .widget<TextField>(searchField)
            .onSubmitted
            ?.call('unique_target_word');
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();

        expect(find.text('1 / 1'), findsOneWidget);
        expect(find.text('RESPONSE HEADERS'), findsOneWidget);

        expect(find.text('REQUEST HEADERS', skipOffstage: false), findsNothing);
        expect(find.text('ERROR SUMMARY', skipOffstage: false), findsNothing);

        await tester.enterText(searchField, 'critical_failure_token');
        tester
            .widget<TextField>(searchField)
            .onSubmitted
            ?.call('critical_failure_token');
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('1 / 1'), findsOneWidget);
        expect(find.text('ERROR SUMMARY', skipOffstage: false), findsOneWidget);

        expect(find.text('REQUEST HEADERS', skipOffstage: false), findsNothing);
        expect(
            find.text('RESPONSE HEADERS', skipOffstage: false), findsOneWidget);
      },
    );

    testWidgets(
      'Rapid tab switching across all tabs does not throw exceptions or corrupt state',
      (tester) async {
        final entry = _createEntry('rapid_tab_1');
        final record = RequestRecord(
          id: 'rapid_tab_1',
          method: 'GET',
          url: 'https://api.example.com/rapid_tab_1',
          statusCode: 200,
          durationMs: 30,
          requestSizeBytes: 100,
          responseSizeBytes: 200,
          timestamp: DateTime(2026, 1, 1),
          requestHeaders: const {'header_r': 'val_r'},
          responseHeaders: const {'header_s': 'val_s'},
          requestContentType: 'application/json',
          responseContentType: 'application/json',
          requestBodyPreview: '{"req":1}',
          responseBodyPreview: '{"res":2}',
        );

        final controller = _MockDetailScopeController(record: record);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InterceptlyScope(
                controller: controller,
                child: RequestDetailPage(entry: entry),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final tabOverview = find.text('Overview');
        final tabRequest = find.text('Request');
        final tabResponse = find.text('Response');
        final tabError = find.text('Error');

        for (var cycle = 0; cycle < 5; cycle++) {
          await tester.tap(tabResponse);
          await tester.pump(const Duration(milliseconds: 20));
          await tester.tap(tabRequest);
          await tester.pump(const Duration(milliseconds: 20));
          await tester.tap(tabError);
          await tester.pump(const Duration(milliseconds: 20));
          await tester.tap(tabOverview);
          await tester.pump(const Duration(milliseconds: 20));
        }

        await tester.pumpAndSettle();

        expect(find.text('URL'), findsOneWidget);
        expect(
            find.text('REQUEST HEADERS', skipOffstage: false), findsOneWidget);
        expect(
            find.text('RESPONSE HEADERS', skipOffstage: false), findsOneWidget);
      },
    );

    testWidgets(
      'Search navigation Next/Prev match cycling across tabs under rapid interactions',
      (tester) async {
        final entry = _createEntry('cycle_nav_1');
        final record = RequestRecord(
          id: 'cycle_nav_1',
          method: 'GET',
          url: 'https://api.example.com/cycle_nav_1/common_tag',
          statusCode: 200,
          durationMs: 30,
          requestSizeBytes: 100,
          responseSizeBytes: 200,
          timestamp: DateTime(2026, 1, 1),
          requestHeaders: const {'custom_header': 'common_tag_in_request'},
          responseHeaders: const {'custom_header': 'common_tag_in_response'},
          requestContentType: 'application/json',
          responseContentType: 'application/json',
          requestBodyPreview: '{"name":"common_tag"}',
          responseBodyPreview: '{"name":"common_tag"}',
          errorMessage: 'common_tag error',
        );

        final controller = _MockDetailScopeController(record: record);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InterceptlyScope(
                controller: controller,
                child: RequestDetailPage(entry: entry),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final searchField = find.byType(TextField);
        await tester.enterText(searchField, 'common_tag');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();

        final nextMatchButton = find.byTooltip('Next match');
        final prevMatchButton = find.byTooltip('Previous match');

        expect(nextMatchButton, findsOneWidget);
        expect(prevMatchButton, findsOneWidget);

        for (var i = 0; i < 15; i++) {
          await tester.tap(nextMatchButton);
          await tester.pump(const Duration(milliseconds: 30));
        }
        await tester.pumpAndSettle();

        for (var i = 0; i < 15; i++) {
          await tester.tap(prevMatchButton);
          await tester.pump(const Duration(milliseconds: 30));
        }
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'WebSocket detail page (2 tabs: Overview, Messages) lazy loading and boundary tabs',
      (tester) async {
        final wsEntry = _createEntry('ws_1', method: 'WS');
        final record = RequestRecord(
          id: 'ws_1',
          method: 'WS',
          url: 'https://api.example.com/ws_1',
          statusCode: 101,
          durationMs: 500,
          requestSizeBytes: 0,
          responseSizeBytes: 0,
          timestamp: DateTime(2026, 1, 1),
          requestHeaders: const {},
          responseHeaders: const {},
        );

        final controller = _MockDetailScopeController(record: record);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InterceptlyScope(
                controller: controller,
                child: RequestDetailPage(entry: wsEntry),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Overview'), findsOneWidget);
        expect(find.text('Messages'), findsOneWidget);
        expect(find.text('Request'), findsNothing);
        expect(find.text('Response'), findsNothing);
        expect(find.text('Error'), findsNothing);

        await tester.tap(find.text('Messages'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });
}
