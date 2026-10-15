import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/session/memory_index.dart';

void main() {
  setUp(() async {
    await InspectorSession.resetForTesting();
  });

  tearDown(() async {
    await InspectorSession.resetForTesting();
  });

  test('MemoryIndex drops oldest entry when maxEntries is exceeded', () {
    final index = MemoryIndex(maxEntries: 2);

    final e1 = _buildEntry('1');
    final e2 = _buildEntry('2');
    final e3 = _buildEntry('3');

    index.add(e1);
    index.add(e2);
    index.add(e3);

    expect(index.length, 2);
    expect(index.entries.first.id, '3');
    expect(index.entries.last.id, '2');
  });

  test('MemoryIndex filter by method', () {
    final index = MemoryIndex(maxEntries: 100);
    index.add(_buildEntry('1', method: 'GET'));
    index.add(_buildEntry('2', method: 'POST'));
    index.add(_buildEntry('3', method: 'GET'));

    final filtered = index.filtered(RequestFilter(methods: {'POST'}));
    expect(filtered.length, 1);
    expect(filtered.first.id, '2');
  });

  test('MemoryIndex filter by status code range', () {
    final index = MemoryIndex(maxEntries: 100);
    index.add(_buildEntry('1', statusCode: 200));
    index.add(_buildEntry('2', statusCode: 404));

    final filtered = index.filtered(
      RequestFilter(include2xx: false, include3xx: false, include5xx: false),
    );
    expect(filtered.length, 1);
    expect(filtered.first.id, '2');
  });

  test('MemoryIndex clear resets entries and emits empty list', () async {
    final index = MemoryIndex(maxEntries: 100);
    index.add(_buildEntry('1'));

    index.clear();
    await Future<void>.delayed(Duration.zero);

    expect(index.length, 0);
  });

  test('InspectorSession singleton is shared', () {
    final a = InspectorSession.instance;
    final b = InspectorSession.instance;
    expect(identical(a, b), isTrue);
  });

  test('Interceptly.init uses shared session by default', () {
    final a = InspectorSession.instance;
    final b = InspectorSession.instance;
    expect(identical(a, b), isTrue);
  });

  test(
    'MemoryIndex updates pending entry in-place without duplicating rows when preceding items exist',
    () {
      final index = MemoryIndex(maxEntries: 100);
      final reqA = _buildEntry('reqA', statusCode: 0);
      final reqB = _buildEntry('reqB', statusCode: 0);
      final reqACompleted = _buildEntry('reqA', statusCode: 200);

      index.add(reqA);
      index.add(reqB);
      expect(index.length, 2);

      index.add(reqACompleted);

      expect(index.length, 2);
      expect(index.entries.where((e) => e.id == 'reqA').length, 1);
      expect(index.entries.firstWhere((e) => e.id == 'reqA').statusCode, 200);
      expect(index.entries[0].id, 'reqB');
      expect(index.entries[1].id, 'reqA');
      expect(index.entries[1].statusCode, 200);

      final reqBCompleted = _buildEntry('reqB', statusCode: 404);
      index.add(reqBCompleted);
      expect(index.length, 2);
      expect(index.entries[0].id, 'reqB');
      expect(index.entries[0].statusCode, 404);
      expect(index.entries[1].id, 'reqA');
      expect(index.entries[1].statusCode, 200);
    },
  );

  test(
    'MemoryIndex handles interleaved completions for many concurrent in-flight requests',
    () {
      final index = MemoryIndex(maxEntries: 100);
      final reqs = List.generate(5, (i) => _buildEntry('req$i', statusCode: 0));
      for (final req in reqs) {
        index.add(req);
      }
      expect(index.length, 5);

      index.add(_buildEntry('req2', statusCode: 200));
      expect(index.length, 5);
      expect(index.entries.firstWhere((e) => e.id == 'req2').statusCode, 200);

      index.add(_buildEntry('req0', statusCode: 500));
      expect(index.length, 5);
      expect(index.entries.firstWhere((e) => e.id == 'req0').statusCode, 500);

      index.add(_buildEntry('req4', statusCode: 204));
      expect(index.length, 5);
      expect(index.entries.firstWhere((e) => e.id == 'req4').statusCode, 204);

      final ids = index.entries.map((e) => e.id).toSet();
      expect(ids.length, 5);
    },
  );

  test('InspectorSession invalidates grouped cache on toggleGrouping',
      () async {
    final session = InspectorSession();
    session.recordPending(
      id: 'req1',
      method: 'GET',
      url: 'https://api.example.com/items',
      timestamp: DateTime(2026, 1, 1),
    );

    final initialGroups = session.getGroupedRecords();
    expect(initialGroups.length, 1);

    session.toggleGrouping(true);
    final enabledGroups = session.getGroupedRecords();
    expect(enabledGroups.length, 1);
    expect(session.groupingEnabled, isTrue);

    session.toggleGrouping(false);
    final disabledGroups = session.getGroupedRecords();
    expect(disabledGroups.length, 1);
    expect(session.groupingEnabled, isFalse);

    await session.dispose();
  });

  test(
    'InspectorSession.getGroupedRecords() updates expanded state immediately when toggleDomainExpanded() is called',
    () async {
      final session = InspectorSession();
      session.recordPending(
        id: 'req1',
        method: 'GET',
        url: 'https://api.example.com/items',
        timestamp: DateTime(2026, 1, 1),
      );

      var groups = session.getGroupedRecords();
      expect(groups.length, 1);
      expect(groups.first.domain, 'api.example.com');
      expect(groups.first.isExpanded, isTrue);

      session.toggleDomainExpanded('api.example.com');
      groups = session.getGroupedRecords();
      expect(groups.first.isExpanded, isFalse);

      session.toggleDomainExpanded('api.example.com');
      groups = session.getGroupedRecords();
      expect(groups.first.isExpanded, isTrue);

      await session.dispose();
    },
  );

  test('InspectorSession resets _instance singleton to null upon dispose()',
      () async {
    final instance1 = InspectorSession.instance;
    await instance1.dispose();
    final instance2 = InspectorSession.instance;
    expect(identical(instance1, instance2), isFalse);
    await instance2.dispose();
  });

  test('Interceptly resets _sharedInstance singleton to null upon dispose()',
      () {
    final instance1 = Interceptly.instance;
    instance1.dispose();
    final instance2 = Interceptly.instance;
    expect(identical(instance1, instance2), isFalse);
    instance2.dispose();
  });

  test('InspectorSession.resetForTesting resets singleton and Interceptly',
      () async {
    final session1 = InspectorSession.instance;
    final interceptly1 = Interceptly.instance;
    await InspectorSession.resetForTesting();
    final session2 = InspectorSession.instance;
    final interceptly2 = Interceptly.instance;
    expect(identical(session1, session2), isFalse);
    expect(identical(interceptly1, interceptly2), isFalse);
  });
}

IndexEntry _buildEntry(
  String id, {
  String method = 'GET',
  String url = 'https://example.com/test',
  int statusCode = 200,
}) {
  return IndexEntry(
    id: id,
    method: method,
    url: url,
    statusCode: statusCode,
    requestTruncation: const BodyTruncation.complete(0),
    responseTruncation: const BodyTruncation.complete(0),
    durationMs: 20,
    requestSizeBytes: 0,
    responseSizeBytes: 0,
    timestamp: DateTime(2026, 1, 1),
    hasError: false,
    bodyLocation: BodyLocation.memory,
  );
}
