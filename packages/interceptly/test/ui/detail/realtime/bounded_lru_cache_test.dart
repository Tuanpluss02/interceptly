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

      // Add 31st entry: 0 should be evicted as least recently used
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

      // Read key 1 to promote it to most recently used
      expect(cache[1], equals('one'));

      // Adding key 4 should now evict key 2 (which is now the oldest)
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

    test('updating an existing entry refreshes LRU order without increasing size', () {
      final cache = BoundedLruCache<int, String>(capacity: 3);
      cache[1] = 'one';
      cache[2] = 'two';
      cache[3] = 'three';

      // Update key 1
      cache[1] = 'updated-one';
      expect(cache.length, equals(3));

      // Adding key 4 should evict key 2
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

      // Access key 1 via putIfAbsent
      final v1 = cache.putIfAbsent(1, () => 'new-one');
      expect(v1, equals('one'));

      // Add key 4: key 2 should be evicted
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

    test('tryParseJsonPayload works with BoundedLruCache and evicts beyond capacity 30', () {
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

      // Maximum 30 entries retained
      expect(cache.length, equals(30));
      // First 5 entries (0-4) should have been evicted
      expect(cache.containsKey('frame_0'), isFalse);
      expect(cache.containsKey('frame_4'), isFalse);
      // Later entries should still be present
      expect(cache.containsKey('frame_5'), isTrue);
      expect(cache.containsKey('frame_34'), isTrue);
    });
  });
}
