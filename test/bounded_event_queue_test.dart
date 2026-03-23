import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/session/bounded_event_queue.dart';

void main() {
  // ── basic operations ──────────────────────────────────────────────────────

  group('BoundedEventQueue basic operations', () {
    test('starts empty', () {
      final q = BoundedEventQueue<int>(maxSize: 5);
      expect(q.isEmpty, isTrue);
      expect(q.length, 0);
    });

    test('add increases length', () {
      final q = BoundedEventQueue<int>(maxSize: 5);
      q.add(1);
      q.add(2);
      expect(q.length, 2);
      expect(q.isEmpty, isFalse);
    });

    test('removeFirstOrNull returns items in FIFO order', () {
      final q = BoundedEventQueue<int>(maxSize: 5);
      q.add(10);
      q.add(20);
      expect(q.removeFirstOrNull(), 10);
      expect(q.removeFirstOrNull(), 20);
    });

    test('removeFirstOrNull returns null when empty', () {
      final q = BoundedEventQueue<int>(maxSize: 5);
      expect(q.removeFirstOrNull(), isNull);
    });
  });

  // ── overflow / drop ───────────────────────────────────────────────────────

  group('BoundedEventQueue overflow', () {
    test('drops oldest entry when maxSize is exceeded', () {
      final q = BoundedEventQueue<int>(maxSize: 2);
      q.add(1);
      q.add(2);
      q.add(3); // should drop 1

      expect(q.length, 2);
      expect(q.removeFirstOrNull(), 2);
      expect(q.removeFirstOrNull(), 3);
    });

    test('droppedCount increments for each dropped entry', () {
      final q = BoundedEventQueue<int>(maxSize: 2);
      q.add(1);
      q.add(2);
      q.add(3);
      q.add(4);

      expect(q.droppedCount, 2);
    });

    test('droppedCount starts at zero', () {
      expect(BoundedEventQueue<int>(maxSize: 5).droppedCount, 0);
    });
  });

  // ── clear ─────────────────────────────────────────────────────────────────

  group('BoundedEventQueue.clear', () {
    test('empties the queue', () {
      final q = BoundedEventQueue<int>(maxSize: 5);
      q.add(1);
      q.add(2);
      q.clear();

      expect(q.isEmpty, isTrue);
      expect(q.length, 0);
    });

    test('resets droppedCount', () {
      final q = BoundedEventQueue<int>(maxSize: 1);
      q.add(1);
      q.add(2); // drops 1
      expect(q.droppedCount, 1);

      q.clear();
      expect(q.droppedCount, 0);
    });
  });

  // ── assert ────────────────────────────────────────────────────────────────

  test('asserts maxSize > 0', () {
    expect(() => BoundedEventQueue<int>(maxSize: 0), throwsA(isA<AssertionError>()));
  });
}
