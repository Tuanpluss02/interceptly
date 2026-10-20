// ignore_for_file: invalid_use_of_internal_member
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/ui/search/master_search_controller.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';

void main() {
  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('MasterSearchController Dynamic Updates', () {
    test(
        'updateOrAddEntry replaces pending entry with completed entry in search results',
        () async {
      final search = MasterSearchController();
      addTearDown(search.dispose);

      final pendingEntry = _createEntry(
        id: 'req-1',
        method: 'POST',
        url: 'https://api.example.com/checkout',
        statusCode: 0,
      );

      await search.start(
        query: 'checkout',
        allEntries: [pendingEntry],
        filePath: null,
      );

      expect(search.results, isNotNull);
      expect(search.results!.length, equals(1));
      expect(search.results!.first.statusCode, equals(0));

      final completedEntry = pendingEntry.copyWith(
        statusCode: 200,
        durationMs: 150,
      );

      search.updateOrAddEntry(completedEntry);

      expect(search.results!.length, equals(1));
      expect(search.results!.first.statusCode, equals(200));
      expect(search.results!.first.durationMs, equals(150));
    });

    test(
        'updateOrAddEntry inserts newly arrived matching entry into search results',
        () async {
      final search = MasterSearchController();
      addTearDown(search.dispose);

      await search.start(
        query: 'orders',
        allEntries: [],
        filePath: null,
      );

      expect(search.results, isEmpty);

      final newEntry = _createEntry(
        id: 'req-new',
        method: 'GET',
        url: 'https://api.example.com/orders',
        statusCode: 200,
        durationMs: 40,
      );

      search.updateOrAddEntry(newEntry);

      expect(search.results!.length, equals(1));
      expect(search.results!.first.id, equals('req-new'));
    });

    test(
        'updateOrAddEntry removes entry from search results when it no longer matches',
        () async {
      final search = MasterSearchController();
      addTearDown(search.dispose);

      final errorEntry = _createEntry(
        id: 'req-err',
        method: 'GET',
        url: 'https://api.example.com/items',
        statusCode: 500,
        errorMessage: 'Network timeout',
        hasError: true,
      );

      await search.start(
        query: 'timeout',
        allEntries: [errorEntry],
        filePath: null,
      );

      expect(search.results!.length, equals(1));

      final resolvedEntry = _createEntry(
        id: 'req-err',
        method: 'GET',
        url: 'https://api.example.com/items',
        statusCode: 200,
      );

      search.updateOrAddEntry(resolvedEntry);

      expect(search.results, isEmpty);
    });

    test('pruneMissing removes entries not in validIds and notifies listeners',
        () async {
      final search = MasterSearchController();
      addTearDown(search.dispose);

      final entry1 = _createEntry(
        id: '1',
        method: 'GET',
        url: 'https://api.example.com/item1',
        statusCode: 200,
      );
      final entry2 = _createEntry(
        id: '2',
        method: 'GET',
        url: 'https://api.example.com/item2',
        statusCode: 200,
      );

      await search.start(
        query: 'item',
        allEntries: [entry1, entry2],
        filePath: null,
      );

      expect(search.results?.length, equals(2));

      var notifications = 0;
      search.addListener(() => notifications++);

      search.pruneMissing({'1'});

      expect(search.results?.length, equals(1));
      expect(search.results?.first.id, equals('1'));
    });

    test(
        'active master search in InterceptlyScopeController picks up new engine entries and prunes evicted ones',
        () async {
      final engine = InterceptlyEngine();
      final scope = InterceptlyScopeController(engine: engine);
      addTearDown(scope.dispose);
      addTearDown(engine.dispose);

      engine.recordPending(
        id: '1',
        method: 'GET',
        url: 'https://api.example.com/items',
        timestamp: DateTime(2026, 1, 1),
      );
      engine.flushPendingNotifications();

      await scope.startMasterSearch('orders');
      expect(scope.entries, isEmpty);

      engine.recordPending(
        id: '2',
        method: 'POST',
        url: 'https://api.example.com/orders',
        timestamp: DateTime(2026, 1, 1),
      );
      engine.flushPendingNotifications();

      expect(scope.entries.map((e) => e.id), contains('2'));
    });

    test(
        'updateOrAddEntry preserves existing file-backed body matches across traffic updates',
        () async {
      final search = MasterSearchController();
      addTearDown(search.dispose);

      final fileEntry = _createEntry(
        id: 'file-1',
        method: 'POST',
        url: 'https://api.example.com/upload',
        statusCode: 200,
        bodyLocation: BodyLocation.file,
      );

      await search.start(
        query: 'secret-token',
        allEntries: [],
        filePath: null,
      );

      search.recordFileMatchForTesting(fileEntry);
      expect(search.results?.length, equals(1));

      search.updateOrAddEntry(fileEntry.copyWith(statusCode: 204));

      expect(search.results?.map((e) => e.id), contains('file-1'));
      expect(search.results?.first.statusCode, equals(204));
    });

    test(
        'InterceptlyScopeController skips search reconciliation when entriesVersion is unchanged',
        () async {
      final engine = InterceptlyEngine();
      final scope = InterceptlyScopeController(engine: engine);
      addTearDown(scope.dispose);
      addTearDown(engine.dispose);

      engine.recordPending(
        id: '1',
        method: 'GET',
        url: 'https://api.example.com/test',
        timestamp: DateTime(2026, 1, 1),
      );
      engine.flushPendingNotifications();

      await scope.startMasterSearch('test');
      expect(scope.entries.length, equals(1));

      final initialVersion = engine.entriesVersion;
      await engine.recordRealtimeFrame(
        RealtimeFrame(
          id: 'frame-1',
          sessionId: '1',
          timestamp: DateTime(2026, 1, 1),
          direction: FrameDirection.incoming,
          type: FrameType.text,
          textPayload: 'frame data',
        ),
      );

      expect(engine.entriesVersion, equals(initialVersion));
      expect(scope.entries.length, equals(1));
    });
  });

  group('InterceptlyEngine Search Invalidation and Coalescing', () {
    test(
        'search updates invalidate grouped cache in InterceptlyScopeController',
        () async {
      final engine = InterceptlyEngine();
      final scope = InterceptlyScopeController(engine: engine);
      addTearDown(scope.dispose);
      addTearDown(engine.dispose);

      engine.recordPending(
        id: '1',
        method: 'GET',
        url: 'https://api.example.com/test',
        timestamp: DateTime(2026, 1, 1),
      );

      final initialGroups = scope.getGroupedRecords();
      expect(initialGroups.length, equals(1));

      await scope.startMasterSearch('test');

      final searchGroups = scope.getGroupedRecords();
      expect(searchGroups.length, equals(1));
    });

    test('recordPending coalesces notifications to prevent UI thrashing',
        () async {
      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);

      var notificationCount = 0;
      engine.addListener(() {
        notificationCount++;
      });

      for (var i = 0; i < 10; i++) {
        engine.recordPending(
          id: 'rapid-$i',
          method: 'GET',
          url: 'https://api.example.com/rapid/$i',
          timestamp: DateTime(2026, 1, 1),
        );
      }

      expect(notificationCount, lessThan(10));

      engine.flushPendingNotifications();
      expect(notificationCount, equals(1));
    });
  });
}

IndexEntry _createEntry({
  required String id,
  required String method,
  required String url,
  required int statusCode,
  int durationMs = 0,
  int requestSizeBytes = 0,
  int responseSizeBytes = 0,
  bool hasError = false,
  String? errorMessage,
  Map<String, String> requestHeaders = const {},
  Map<String, String> responseHeaders = const {},
  BodyLocation bodyLocation = BodyLocation.memory,
}) {
  return IndexEntry(
    id: id,
    method: method,
    url: url,
    statusCode: statusCode,
    durationMs: durationMs,
    requestSizeBytes: requestSizeBytes,
    responseSizeBytes: responseSizeBytes,
    timestamp: DateTime(2026, 1, 1),
    hasError: hasError,
    requestTruncation: const BodyTruncation.complete(0),
    responseTruncation: const BodyTruncation.complete(0),
    requestHeaders: requestHeaders,
    responseHeaders: responseHeaders,
    errorMessage: errorMessage,
    bodyLocation: bodyLocation,
  );
}
