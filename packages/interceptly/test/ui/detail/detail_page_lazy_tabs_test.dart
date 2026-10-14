import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/domain_group.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/session/inspector_preferences.dart';
import 'package:interceptly/src/session/memory_index.dart';
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

IndexEntry _buildEntry(String id, {int statusCode = 200, int durationMs = 10}) {
  return IndexEntry(
    id: id,
    method: 'GET',
    url: 'https://api.example.com/items/$id',
    statusCode: statusCode,
    durationMs: durationMs,
    requestSizeBytes: 128,
    responseSizeBytes: 256,
    timestamp: DateTime(2026, 1, 1),
    hasError: statusCode >= 400 || statusCode == 0,
    requestTruncation: const BodyTruncation.complete(0),
    responseTruncation: const BodyTruncation.complete(0),
    bodyLocation: BodyLocation.memory,
  );
}

void main() {
  group('R1 - RequestDetailPage True Lazy Tabs', () {
    testWidgets(
      'unvisited tabs remain unmounted until user navigates to them',
      (tester) async {
        final entry = _buildEntry('lazy_1');
        final record = RequestRecord(
          id: 'lazy_1',
          method: 'POST',
          url: 'https://api.example.com/items/lazy_1',
          statusCode: 200,
          durationMs: 45,
          requestSizeBytes: 50,
          responseSizeBytes: 120,
          timestamp: DateTime(2026, 1, 1),
          requestHeaders: const {'content-type': 'application/json'},
          responseHeaders: const {'content-type': 'application/json'},
          requestContentType: 'application/json',
          responseContentType: 'application/json',
          requestBodyPreview: '{"name":"item_name"}',
          responseBodyPreview: '{"id":"lazy_1","status":"created"}',
        );

        final session = _FakeSession(record: record, entry: entry);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RequestDetailPage(entry: entry, session: session),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('URL'), findsOneWidget);
        expect(find.text('Request Headers'), findsNothing);
        expect(find.text('Response Headers'), findsNothing);

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        expect(find.text('REQUEST HEADERS'), findsNothing);
        expect(find.text('RESPONSE HEADERS'), findsNothing);

        await tester.tap(find.text('Response'));
        await tester.pumpAndSettle();

        expect(find.text('RESPONSE HEADERS'), findsOneWidget);
        expect(find.text('REQUEST HEADERS'), findsNothing);

        await tester.tap(find.text('Request'));
        await tester.pumpAndSettle();

        expect(find.text('REQUEST HEADERS'), findsOneWidget);
        expect(
            find.text('RESPONSE HEADERS', skipOffstage: false), findsOneWidget);
      },
    );
  });

  group('R1 - MemoryIndex Ring Buffer O(1) Operations', () {
    test('enforces fixed capacity and newest-first order with O(1) eviction',
        () {
      final index = MemoryIndex(maxEntries: 3);
      expect(index.length, 0);
      expect(index.entries, isEmpty);

      index.add(_buildEntry('1'));
      index.add(_buildEntry('2'));
      index.add(_buildEntry('3'));
      expect(index.length, 3);
      expect(index.entries.map((e) => e.id).toList(), ['3', '2', '1']);

      index.add(_buildEntry('4'));
      expect(index.length, 3);
      expect(index.entries.map((e) => e.id).toList(), ['4', '3', '2']);
      expect(index.byId('1'), isNull);
      expect(index.get('1'), isNull);
      expect(index.byId('4')?.id, '4');
      expect(index.get('4')?.id, '4');
    });

    test('updates in-place without reordering or shifting other entries', () {
      final index = MemoryIndex(maxEntries: 4);
      index.add(_buildEntry('1', statusCode: 0));
      index.add(_buildEntry('2', statusCode: 0));
      index.add(_buildEntry('3', statusCode: 0));

      expect(index.entries.map((e) => e.id).toList(), ['3', '2', '1']);

      final updated2 = _buildEntry('2', statusCode: 200, durationMs: 99);
      index.add(updated2);

      expect(index.length, 3);
      expect(index.entries.map((e) => e.id).toList(), ['3', '2', '1']);
      expect(index.entries[1].statusCode, 200);
      expect(index.entries[1].durationMs, 99);
      expect(index.byId('2')?.statusCode, 200);
      expect(index.get('2')?.durationMs, 99);
    });

    test('clamps maxEntries <= 0 to 1 on add', () {
      final zeroIndex = MemoryIndex(maxEntries: 0);
      expect(() => zeroIndex.add(_buildEntry('x')), returnsNormally);
      expect(zeroIndex.length, 1);
      expect(zeroIndex.entries.single.id, 'x');

      final negativeIndex = MemoryIndex(maxEntries: -5);
      expect(() => negativeIndex.add(_buildEntry('y')), returnsNormally);
      expect(negativeIndex.length, 1);
      expect(negativeIndex.entries.single.id, 'y');
    });

    test('clear resets count, head, and direct lookup map', () {
      final index = MemoryIndex(maxEntries: 5);
      index.add(_buildEntry('a'));
      index.add(_buildEntry('b'));
      index.add(_buildEntry('c'));
      expect(index.length, 3);

      index.clear();
      expect(index.length, 0);
      expect(index.entries, isEmpty);
      expect(index.byId('a'), isNull);
      expect(index.get('b'), isNull);

      index.add(_buildEntry('d'));
      expect(index.length, 1);
      expect(index.entries.first.id, 'd');
    });

    test('scales with O(1) insertion across 10,000 items', () {
      final index = MemoryIndex(maxEntries: 5000);
      final stopwatch = Stopwatch()..start();

      for (var i = 0; i < 10000; i++) {
        index.add(_buildEntry('req_$i'));
      }
      stopwatch.stop();

      expect(index.length, 5000);
      expect(index.entries.first.id, 'req_9999');
      expect(index.entries.last.id, 'req_5000');
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });
  });

}
