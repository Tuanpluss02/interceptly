// ignore_for_file: invalid_use_of_internal_member
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/engine/memory_index.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';

void main() {
  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
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

  test('InterceptlyEngine singleton is shared', () {
    final a = InterceptlyEngine.instance;
    final b = InterceptlyEngine.instance;
    expect(identical(a, b), isTrue);
  });

  test('Interceptly.engine uses shared engine by default', () {
    final a = InterceptlyEngine.instance;
    final b = Interceptly.engine;
    expect(identical(a, b), isTrue);
  });

  test('Interceptly public facade delegates correctly to engine', () {
    final facade = Interceptly.instance;
    expect(facade.entries, equals(Interceptly.engine.entries));
    expect(facade.calls, equals(Interceptly.engine.entries));
    expect(facade.droppedEvents, equals(Interceptly.engine.droppedCount));
    expect(facade.isEnabled, equals(Interceptly.engine.isEnabled));
    expect(
        facade.networkSimulation, equals(Interceptly.engine.networkSimulation));
    expect(facade.settings, equals(Interceptly.engine.settings));

    facade.disable();
    expect(facade.isEnabled, isFalse);
    facade.enable();
    expect(facade.isEnabled, isTrue);

    facade.configure(const InterceptlySettings(maxEntries: 42));
    expect(facade.settings.maxEntries, equals(42));
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

  test('InterceptlyScopeController invalidates grouped cache on toggleGrouping',
      () async {
    final engine = InterceptlyEngine();
    final scope = InterceptlyScopeController(engine: engine);
    engine.recordPending(
      id: 'req1',
      method: 'GET',
      url: 'https://api.example.com/items',
      timestamp: DateTime(2026, 1, 1),
    );

    final initialGroups = scope.getGroupedRecords();
    expect(initialGroups.length, 1);

    scope.toggleGrouping(true);
    final enabledGroups = scope.getGroupedRecords();
    expect(enabledGroups.length, 1);
    expect(scope.groupingEnabled, isTrue);

    scope.toggleGrouping(false);
    final disabledGroups = scope.getGroupedRecords();
    expect(disabledGroups.length, 1);
    expect(scope.groupingEnabled, isFalse);

    scope.dispose();
    await engine.dispose();
  });

  test(
    'InterceptlyScopeController.getGroupedRecords() updates expanded state immediately when toggleDomainExpanded() is called',
    () async {
      final engine = InterceptlyEngine();
      final scope = InterceptlyScopeController(engine: engine);
      engine.recordPending(
        id: 'req1',
        method: 'GET',
        url: 'https://api.example.com/items',
        timestamp: DateTime(2026, 1, 1),
      );

      var groups = scope.getGroupedRecords();
      expect(groups.length, 1);
      expect(groups.first.domain, 'api.example.com');
      expect(groups.first.isExpanded, isTrue);

      scope.toggleDomainExpanded('api.example.com');
      groups = scope.getGroupedRecords();
      expect(groups.first.isExpanded, isFalse);

      scope.toggleDomainExpanded('api.example.com');
      groups = scope.getGroupedRecords();
      expect(groups.first.isExpanded, isTrue);

      scope.dispose();
      await engine.dispose();
    },
  );

  test('InterceptlyEngine resets _instance singleton to null upon dispose()',
      () async {
    final instance1 = InterceptlyEngine.instance;
    await instance1.dispose();
    final instance2 = InterceptlyEngine.instance;
    expect(identical(instance1, instance2), isFalse);
    await instance2.dispose();
  });

  test('Interceptly.resetForTesting resets underlying engine singleton',
      () async {
    final engine1 = InterceptlyEngine.instance;
    await Interceptly.resetForTesting();
    final engine2 = InterceptlyEngine.instance;
    expect(identical(engine1, engine2), isFalse);
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
