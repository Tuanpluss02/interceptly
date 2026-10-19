// ignore_for_file: invalid_use_of_internal_member
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/engine/master_search_controller.dart';
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

      // Updated entry resolved without error message
      final resolvedEntry = _createEntry(
        id: 'req-err',
        method: 'GET',
        url: 'https://api.example.com/items',
        statusCode: 200,
      );

      search.updateOrAddEntry(resolvedEntry);

      expect(search.results, isEmpty);
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

      // Populate grouped cache
      final initialGroups = scope.getGroupedRecords();
      expect(initialGroups.length, equals(1));

      // Trigger search which should invalidate grouped cache and reflect in entries
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

      // Rapidly record 10 pending requests
      for (var i = 0; i < 10; i++) {
        engine.recordPending(
          id: 'rapid-$i',
          method: 'GET',
          url: 'https://api.example.com/rapid/$i',
          timestamp: DateTime(2026, 1, 1),
        );
      }

      // Notification should NOT have fired 10 times synchronously
      expect(notificationCount, lessThan(10));

      // Flush notifications
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
