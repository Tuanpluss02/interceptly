import 'dart:collection';

/// Bounded FIFO queue that drops the oldest event on overflow.
///
/// Capacities below 1 are clamped to 1 so misconfiguration degrades to a
/// single-slot queue instead of crashing.
class BoundedEventQueue<T> {
  BoundedEventQueue({required int maxSize})
      : maxSize = maxSize < 1 ? 1 : maxSize;

  int maxSize;
  final Queue<T> _items = Queue<T>();
  int _droppedCount = 0;

  /// Changes capacity, counting already-queued overflow as dropped.
  ///
  /// Values below 1 are clamped to 1 instead of throwing.
  void updateMaxSize(int value) {
    maxSize = value < 1 ? 1 : value;
    while (_items.length > maxSize) {
      _items.removeFirst();
      _droppedCount++;
    }
  }

  int get length => _items.length;
  int get droppedCount => _droppedCount;
  bool get isEmpty => _items.isEmpty;

  /// Enqueues [value], dropping the oldest entry when full.
  ///
  /// A non-positive [maxSize] (only reachable via direct field mutation)
  /// is clamped back to 1 instead of throwing.
  void add(T value) {
    if (maxSize < 1) {
      maxSize = 1;
    }
    if (_items.length >= maxSize) {
      _items.removeFirst();
      _droppedCount++;
    }
    _items.addLast(value);
  }

  T? removeFirstOrNull() {
    if (_items.isEmpty) {
      return null;
    }
    return _items.removeFirst();
  }

  void clear() {
    _items.clear();
    _droppedCount = 0;
  }
}
