// ignore_for_file: invalid_use_of_internal_member
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('Search and Filter Composition', () {
    test('entries compose both search query and filter criteria simultaneously',
        () async {
      final engine = InterceptlyEngine();
      final scope = InterceptlyScopeController(engine: engine);
      addTearDown(scope.dispose);
      addTearDown(engine.dispose);

      engine.recordPending(
        id: '1',
        method: 'GET',
        url: 'https://api.com/users',
        timestamp: DateTime(2026, 1, 1),
      );
      engine.recordPending(
        id: '2',
        method: 'POST',
        url: 'https://api.com/users',
        timestamp: DateTime(2026, 1, 1),
      );
      engine.recordPending(
        id: '3',
        method: 'POST',
        url: 'https://api.com/posts',
        timestamp: DateTime(2026, 1, 1),
      );

      scope.applyFilter(RequestFilter(methods: {'POST'}));
      expect(scope.entries.length, equals(2));

      await scope.startMasterSearch('users');

      expect(scope.entries.map((e) => e.id).toList(), equals(['2']));

      scope.clearFilter();
      expect(scope.entries.map((e) => e.id).toSet(), equals({'1', '2'}));
    });

    test(
        'onlyErrors filter matches 4xx, 5xx, and network errors but not 2xx or pending',
        () {
      final filter = RequestFilter(onlyErrors: true);
      final ok = IndexEntry(
        id: '1',
        method: 'GET',
        url: 'https://a.com',
        statusCode: 200,
        durationMs: 1,
        requestSizeBytes: 0,
        responseSizeBytes: 0,
        timestamp: DateTime(2026, 1, 1),
        hasError: false,
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation.complete(0),
        bodyLocation: BodyLocation.memory,
      );
      final clientErr = ok.copyWith(id: '2', statusCode: 404, hasError: true);
      final serverErr = ok.copyWith(id: '3', statusCode: 500, hasError: true);
      final netErr = ok.copyWith(id: '4', statusCode: 0, hasError: true);
      final pending = ok.copyWith(id: '5', statusCode: 0, hasError: false);

      expect(filter.matches(ok), isFalse);
      expect(filter.matches(clientErr), isTrue);
      expect(filter.matches(serverErr), isTrue);
      expect(filter.matches(netErr), isTrue);
      expect(filter.matches(pending), isFalse);
    });

    test('statusCode 0 requests respect includePending and onlyErrors', () {
      final base = IndexEntry(
        id: '1',
        method: 'GET',
        url: 'https://a.com',
        statusCode: 0,
        durationMs: 0,
        requestSizeBytes: 0,
        responseSizeBytes: 0,
        timestamp: DateTime(2026, 1, 1),
        hasError: false,
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation.complete(0),
        bodyLocation: BodyLocation.memory,
      );
      final pending = base;
      final netErr = base.copyWith(id: '2', hasError: true);

      final defaultFilter = RequestFilter();
      expect(defaultFilter.matches(pending), isTrue);
      expect(defaultFilter.matches(netErr), isTrue);

      final noPendingFilter = RequestFilter(includePending: false);
      expect(noPendingFilter.matches(pending), isFalse);
      expect(noPendingFilter.matches(netErr), isTrue);

      final errorFilter = RequestFilter(onlyErrors: true);
      expect(errorFilter.matches(pending), isFalse);
      expect(errorFilter.matches(netErr), isTrue);
    });

    test(
        'statusCode 0 entries (network error or pending) do not leak into 2xx/3xx filters',
        () {
      final base = IndexEntry(
        id: '1',
        method: 'GET',
        url: 'https://a.com',
        statusCode: 0,
        durationMs: 0,
        requestSizeBytes: 0,
        responseSizeBytes: 0,
        timestamp: DateTime(2026, 1, 1),
        hasError: false,
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation.complete(0),
        bodyLocation: BodyLocation.memory,
      );
      final pending = base;
      final netErr = base.copyWith(id: '2', hasError: true);

      final filter2xxNoPending = RequestFilter(
        include2xx: true,
        include3xx: false,
        include4xx: false,
        include5xx: false,
        includePending: false,
      );
      expect(filter2xxNoPending.matches(pending), isFalse);
      expect(filter2xxNoPending.matches(netErr), isFalse);

      final filter2xx = RequestFilter(
        include2xx: true,
        include3xx: false,
        include4xx: false,
        include5xx: false,
      );
      expect(filter2xx.matches(pending), isTrue);
      expect(filter2xx.matches(netErr), isFalse);

      final filter4xx = RequestFilter(
        include2xx: false,
        include3xx: false,
        include4xx: true,
        include5xx: false,
      );
      expect(filter4xx.matches(pending), isTrue);
      expect(filter4xx.matches(netErr), isTrue);
    });
  });
}
