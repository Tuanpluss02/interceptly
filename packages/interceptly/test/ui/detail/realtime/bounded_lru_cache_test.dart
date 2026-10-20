import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/detail/realtime/bounded_lru_cache.dart';
import 'package:interceptly/src/ui/detail/realtime/realtime_formatters.dart';

void main() {
  group('BoundedLruCache', () {
    test('default capacity is 30', () {
      final cache = BoundedLruCache<String, int>();
      expect(cache.capacity, equals(30));
    });

    test('custom capacity is preserved', () {
      final cache = BoundedLruCache<String, int>(capacity: 5);
      expect(cache.capacity, equals(5));
    });

    test('throws ArgumentError if capacity is <= 0', () {
      expect(
          () => BoundedLruCache<String, int>(capacity: 0), throwsArgumentError);
      expect(() => BoundedLruCache<String, int>(capacity: -1),
          throwsArgumentError);
    });

    test('stores entries up to capacity without eviction', () {
      final cache = BoundedLruCache<int, String>(capacity: 3);
      cache[1] = 'one';
      cache[2] = 'two';
      cache[3] = 'three';

      expect(cache.length, equals(3));
      expect(cache[1], equals('one'));
      expect(cache[2], equals('two'));
      expect(cache[3], equals('three'));
    });

    test('purges oldest accessed entry when capacity 30 is exceeded', () {
      final cache = BoundedLruCache<int, String>(capacity: 30);
      for (var i = 0; i < 30; i++) {
        cache[i] = 'val-$i';
      }
      expect(cache.length, equals(30));
      expect(cache.containsKey(0), isTrue);

      cache[30] = 'val-30';
      expect(cache.length, equals(30));
      expect(cache.containsKey(0), isFalse);
      expect(cache[0], isNull);
      expect(cache.containsKey(30), isTrue);
      expect(cache[30], equals('val-30'));
    });

    test('reading an entry via [] refreshes LRU order', () {
      final cache = BoundedLruCache<int, String>(capacity: 3);
      cache[1] = 'one';
      cache[2] = 'two';
      cache[3] = 'three';

      expect(cache[1], equals('one'));

      cache[4] = 'four';
      expect(cache.length, equals(3));
      expect(cache.containsKey(2), isFalse);
      expect(cache.containsKey(1), isTrue);
      expect(cache.containsKey(3), isTrue);
      expect(cache.containsKey(4), isTrue);
    });

    test('reading an entry via get() refreshes LRU order', () {
      final cache = BoundedLruCache<int, String>(capacity: 3);
      cache[1] = 'one';
      cache[2] = 'two';
      cache[3] = 'three';

      expect(cache.get(1), equals('one'));

      cache[4] = 'four';
      expect(cache.containsKey(2), isFalse);
      expect(cache.containsKey(1), isTrue);
    });

    test(
        'updating an existing entry refreshes LRU order without increasing size',
        () {
      final cache = BoundedLruCache<int, String>(capacity: 3);
      cache[1] = 'one';
      cache[2] = 'two';
      cache[3] = 'three';

      cache[1] = 'updated-one';
      expect(cache.length, equals(3));

      cache[4] = 'four';
      expect(cache.containsKey(2), isFalse);
      expect(cache.containsKey(1), isTrue);
      expect(cache[1], equals('updated-one'));
    });

    test('putIfAbsent inserts new entry and promotes existing entry', () {
      final cache = BoundedLruCache<int, String>(capacity: 3);
      cache[1] = 'one';
      cache[2] = 'two';
      cache[3] = 'three';

      final v1 = cache.putIfAbsent(1, () => 'new-one');
      expect(v1, equals('one'));

      cache.putIfAbsent(4, () => 'four');
      expect(cache.containsKey(2), isFalse);
      expect(cache.containsKey(1), isTrue);
      expect(cache.containsKey(4), isTrue);
    });

    test('remove and clear work correctly', () {
      final cache = BoundedLruCache<int, String>(capacity: 3);
      cache[1] = 'one';
      cache[2] = 'two';

      expect(cache.remove(1), equals('one'));
      expect(cache.containsKey(1), isFalse);
      expect(cache.length, equals(1));

      cache.clear();
      expect(cache.length, equals(0));
      expect(cache.isEmpty, isTrue);
    });

    test(
        'tryParseJsonPayload works with BoundedLruCache and evicts beyond capacity 30',
        () {
      final cache = BoundedLruCache<String, dynamic>(capacity: 30);
      for (var i = 0; i < 35; i++) {
        final frame = RealtimeFrame.memoryText(
          id: 'frame_$i',
          sessionId: 'sess',
          direction: FrameDirection.incoming,
          text: '{"index":$i}',
        );
        final parsed = tryParseJsonPayload(frame, cache);
        expect(parsed, isNotNull);
        expect(parsed['index'], equals(i));
      }

      expect(cache.length, equals(30));
      expect(cache.containsKey('frame_0'), isFalse);
      expect(cache.containsKey('frame_4'), isFalse);
      expect(cache.containsKey('frame_5'), isTrue);
      expect(cache.containsKey('frame_34'), isTrue);
    });
  });
}
