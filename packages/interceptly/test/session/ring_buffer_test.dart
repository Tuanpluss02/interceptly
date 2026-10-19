// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/engine/ring_buffer.dart';

void main() {
  group('RingBuffer basic operations', () {
    test('starts empty', () {
      final buffer = RingBuffer<int>(capacity: 5);
      expect(buffer.isEmpty, isTrue);
      expect(buffer.isNotEmpty, isFalse);
      expect(buffer.length, equals(0));
      expect(buffer.droppedCount, equals(0));
      expect(buffer.toList(), isEmpty);
    });

    test('adds items up to capacity in FIFO order', () {
      final buffer = RingBuffer<String>(capacity: 3);
      buffer.add('a');
      buffer.add('b');

      expect(buffer.length, equals(2));
      expect(buffer.isEmpty, isFalse);
      expect(buffer.isNotEmpty, isTrue);
      expect(buffer[0], equals('a'));
      expect(buffer[1], equals('b'));
      expect(buffer.toList(), equals(['a', 'b']));
      expect(buffer.droppedCount, equals(0));
    });
  });

  group('RingBuffer eviction and overflow', () {
    test('evicts oldest when capacity is exceeded', () {
      final buffer = RingBuffer<int>(capacity: 3);
      buffer.add(1);
      buffer.add(2);
      buffer.add(3);
      buffer.add(4);

      expect(buffer.length, equals(3));
      expect(buffer.droppedCount, equals(1));
      expect(buffer.toList(), equals([2, 3, 4]));
      expect(buffer[0], equals(2));
      expect(buffer[1], equals(3));
      expect(buffer[2], equals(4));

      buffer.add(5);
      expect(buffer.length, equals(3));
      expect(buffer.droppedCount, equals(2));
      expect(buffer.toList(), equals([3, 4, 5]));
    });

    test('updateCapacity trims overflow and updates droppedCount', () {
      final buffer = RingBuffer<int>(capacity: 5);
      for (var i = 1; i <= 5; i++) {
        buffer.add(i);
      }

      buffer.updateCapacity(2);
      expect(buffer.capacity, equals(2));
      expect(buffer.length, equals(2));
      expect(buffer.droppedCount, equals(3));
      expect(buffer.toList(), equals([4, 5]));
    });

    test('updateCapacity allows buffer to grow without dropping items', () {
      final buffer = RingBuffer<int>(capacity: 2);
      buffer.add(1);
      buffer.add(2);
      buffer.updateCapacity(4);
      buffer.add(3);

      expect(buffer.length, equals(3));
      expect(buffer.droppedCount, equals(0));
      expect(buffer.toList(), equals([1, 2, 3]));
    });
  });

  group('RingBuffer clear', () {
    test('wipes all items and resets dropped counter', () {
      final buffer = RingBuffer<int>(capacity: 2);
      buffer.add(1);
      buffer.add(2);
      buffer.add(3);
      expect(buffer.droppedCount, equals(1));

      buffer.clear();
      expect(buffer.length, equals(0));
      expect(buffer.isEmpty, isTrue);
      expect(buffer.droppedCount, equals(0));
      expect(buffer.toList(), isEmpty);
    });
  });

  group('RingBuffer boundaries and errors', () {
    test('clamps capacity <= 0 to 1', () {
      expect(RingBuffer<int>(capacity: 0).capacity, 1);
      expect(RingBuffer<int>(capacity: -1).capacity, 1);
    });

    test('throws RangeError on invalid index', () {
      final buffer = RingBuffer<int>(capacity: 3);
      buffer.add(10);
      expect(() => buffer[-1], throwsA(isA<RangeError>()));
      expect(() => buffer[1], throwsA(isA<RangeError>()));
    });
  });
}
