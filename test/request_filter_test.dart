import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/request_filter.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/body_location.dart';

void main() {
  // ── isEmpty ──────────────────────────────────────────────────────────────

  group('RequestFilter.isEmpty', () {
    test('default constructor is empty', () {
      expect(RequestFilter().isEmpty, isTrue);
    });

    test('non-empty methods makes it non-empty', () {
      expect(RequestFilter(methods: {'GET'}).isEmpty, isFalse);
    });

    test('disabling a status range makes it non-empty', () {
      expect(RequestFilter(include2xx: false).isEmpty, isFalse);
      expect(RequestFilter(include3xx: false).isEmpty, isFalse);
      expect(RequestFilter(include4xx: false).isEmpty, isFalse);
      expect(RequestFilter(include5xx: false).isEmpty, isFalse);
    });

    test('non-empty domains makes it non-empty', () {
      expect(RequestFilter(domains: {'example.com'}).isEmpty, isFalse);
    });

    test('host set makes it non-empty', () {
      expect(RequestFilter(host: 'api.example.com').isEmpty, isFalse);
    });

    test('blank host is treated as empty', () {
      expect(RequestFilter(host: '   ').isEmpty, isTrue);
    });

    test('query set makes it non-empty', () {
      expect(RequestFilter(query: 'search').isEmpty, isFalse);
    });

    test('blank query is treated as empty', () {
      expect(RequestFilter(query: '').isEmpty, isTrue);
    });
  });

  // ── isActive / activeFilterCount ─────────────────────────────────────────

  group('RequestFilter.activeFilterCount', () {
    test('zero for default filter', () {
      expect(RequestFilter().activeFilterCount, 0);
    });

    test('counts methods group once', () {
      expect(RequestFilter(methods: {'GET', 'POST'}).activeFilterCount, 1);
    });

    test('counts status range group once even with multiple bools off', () {
      expect(
        RequestFilter(include2xx: false, include5xx: false).activeFilterCount,
        1,
      );
    });

    test('counts each independent group separately', () {
      final f = RequestFilter(
        methods: {'GET'},
        include2xx: false,
        domains: {'example.com'},
        host: 'api',
        query: 'foo',
      );
      expect(f.activeFilterCount, 5); // methods + status + domains + host + query
    });

    test('all five groups active', () {
      final f = RequestFilter(
        methods: {'GET'},
        include4xx: false,
        domains: {'example.com'},
        host: 'api',
        query: 'foo',
      );
      expect(f.activeFilterCount, 5);
    });
  });

  // ── matches — method ─────────────────────────────────────────────────────

  group('RequestFilter.matches — method', () {
    test('empty methods set passes all methods', () {
      final f = RequestFilter();
      expect(f.matches(_entry(method: 'GET')), isTrue);
      expect(f.matches(_entry(method: 'DELETE')), isTrue);
    });

    test('method filter is case-insensitive', () {
      final f = RequestFilter(methods: {'get'});
      expect(f.matches(_entry(method: 'GET')), isTrue);
      expect(f.matches(_entry(method: 'get')), isTrue);
    });

    test('method filter excludes non-matching methods', () {
      final f = RequestFilter(methods: {'POST'});
      expect(f.matches(_entry(method: 'GET')), isFalse);
      expect(f.matches(_entry(method: 'POST')), isTrue);
    });
  });

  // ── matches — status code ─────────────────────────────────────────────────

  group('RequestFilter.matches — status code', () {
    test('statusCode 0 skips range check', () {
      final f = RequestFilter(include2xx: false);
      expect(f.matches(_entry(statusCode: 0)), isTrue);
    });

    test('include2xx=false excludes 200', () {
      final f = RequestFilter(include2xx: false);
      expect(f.matches(_entry(statusCode: 200)), isFalse);
    });

    test('include3xx=false excludes 301', () {
      final f = RequestFilter(include3xx: false);
      expect(f.matches(_entry(statusCode: 301)), isFalse);
    });

    test('include4xx=false excludes 404', () {
      final f = RequestFilter(include4xx: false);
      expect(f.matches(_entry(statusCode: 404)), isFalse);
    });

    test('include5xx=false excludes 500', () {
      final f = RequestFilter(include5xx: false);
      expect(f.matches(_entry(statusCode: 500)), isFalse);
    });

    test('entry passes when its range is still included', () {
      final f = RequestFilter(include2xx: false, include3xx: false);
      expect(f.matches(_entry(statusCode: 404)), isTrue);
      expect(f.matches(_entry(statusCode: 503)), isTrue);
    });
  });

  // ── matches — domain ──────────────────────────────────────────────────────

  group('RequestFilter.matches — domain', () {
    test('empty domains set passes all entries', () {
      expect(RequestFilter().matches(_entry()), isTrue);
    });

    test('domain filter keeps matching domain', () {
      final f = RequestFilter(domains: {'example.com'});
      expect(f.matches(_entry(url: 'https://example.com/api')), isTrue);
    });

    test('domain filter excludes non-matching domain', () {
      final f = RequestFilter(domains: {'example.com'});
      expect(f.matches(_entry(url: 'https://other.com/api')), isFalse);
    });
  });

  // ── matches — host ────────────────────────────────────────────────────────

  group('RequestFilter.matches — host', () {
    test('host substring match is case-insensitive', () {
      final f = RequestFilter(host: 'API.EXAMPLE');
      expect(f.matches(_entry(url: 'https://api.example.com/v1')), isTrue);
    });

    test('host mismatch excludes entry', () {
      final f = RequestFilter(host: 'other.com');
      expect(f.matches(_entry(url: 'https://api.example.com/v1')), isFalse);
    });

    test('blank host is ignored', () {
      final f = RequestFilter(host: '  ');
      expect(f.matches(_entry(url: 'https://api.example.com/v1')), isTrue);
    });
  });

  // ── matches — query ───────────────────────────────────────────────────────

  group('RequestFilter.matches — query', () {
    test('query matches URL substring', () {
      final f = RequestFilter(query: 'users');
      expect(f.matches(_entry(url: 'https://api.example.com/users/1')), isTrue);
    });

    test('query misses when URL and error do not contain it', () {
      final f = RequestFilter(query: 'notfound');
      expect(f.matches(_entry(url: 'https://api.example.com/users')), isFalse);
    });

    test('query matches errorMessage', () {
      final f = RequestFilter(query: 'timeout');
      expect(
        f.matches(_entry(url: 'https://api.example.com', errorMessage: 'Connection timeout')),
        isTrue,
      );
    });

    test('blank query is ignored', () {
      final f = RequestFilter(query: '');
      expect(f.matches(_entry()), isTrue);
    });
  });

  // ── copyWith ──────────────────────────────────────────────────────────────

  group('RequestFilter.copyWith', () {
    test('preserves unchanged fields', () {
      final original = RequestFilter(methods: {'GET'}, include4xx: false);
      final copy = original.copyWith(query: 'test');
      expect(copy.methods, {'GET'});
      expect(copy.include4xx, isFalse);
      expect(copy.query, 'test');
    });

    test('clearHost sets host to null', () {
      final original = RequestFilter(host: 'api.example.com');
      final copy = original.copyWith(clearHost: true);
      expect(copy.host, isNull);
    });

    test('clearQuery sets query to null', () {
      final original = RequestFilter(query: 'search');
      final copy = original.copyWith(clearQuery: true);
      expect(copy.query, isNull);
    });
  });

  // ── equality & hashCode ───────────────────────────────────────────────────

  group('RequestFilter equality', () {
    test('two default filters are equal', () {
      expect(RequestFilter(), equals(RequestFilter()));
    });

    test('set order does not affect equality', () {
      final a = RequestFilter(methods: {'GET', 'POST'});
      final b = RequestFilter(methods: {'POST', 'GET'});
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different methods are not equal', () {
      expect(RequestFilter(methods: {'GET'}), isNot(equals(RequestFilter(methods: {'POST'}))));
    });

    test('different status flags are not equal', () {
      expect(RequestFilter(include2xx: false), isNot(equals(RequestFilter())));
    });

    test('different query are not equal', () {
      expect(RequestFilter(query: 'a'), isNot(equals(RequestFilter(query: 'b'))));
    });
  });

  // ── unmodifiable sets ─────────────────────────────────────────────────────

  group('RequestFilter unmodifiable sets', () {
    test('methods set is unmodifiable', () {
      final f = RequestFilter(methods: {'GET'});
      expect(() => (f.methods as dynamic).add('POST'), throwsUnsupportedError);
    });

    test('domains set is unmodifiable', () {
      final f = RequestFilter(domains: {'example.com'});
      expect(() => (f.domains as dynamic).add('other.com'), throwsUnsupportedError);
    });
  });

  // ── extractDomain ─────────────────────────────────────────────────────────

  group('RequestFilter.extractDomain', () {
    test('returns host from valid URL', () {
      expect(RequestFilter.extractDomain('https://api.example.com/v1'), 'api.example.com');
    });

    test('returns unknown for unparseable URL', () {
      expect(RequestFilter.extractDomain('not a url'), 'unknown');
    });
  });
}

IndexEntry _entry({
  String method = 'GET',
  String url = 'https://example.com/api',
  int statusCode = 200,
  String? errorMessage,
}) {
  return IndexEntry(
    id: 'test',
    method: method,
    url: url,
    statusCode: statusCode,
    durationMs: 10,
    requestSizeBytes: 0,
    responseSizeBytes: 0,
    timestamp: DateTime(2026),
    hasError: errorMessage != null,
    bodyLocation: BodyLocation.memory,
    errorMessage: errorMessage,
  );
}
