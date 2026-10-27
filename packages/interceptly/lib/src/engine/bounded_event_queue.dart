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

  /// Resets the overflow drop counter without discarding queued items.
  ///
  /// Used after folding [droppedCount] into an owner counter so subsequent
  /// reads do not double-count previously reported drops.
  void resetDroppedCount() {
    _droppedCount = 0;
  }

  /// Enqueues [value], dropping the oldest entry when full.
  ///
  /// Returns the evicted element when an overflow drop occurred, or `null`
  /// when the queue had capacity. Callers that ignore the return value
  /// remain source-compatible.
  ///
  /// A non-positive [maxSize] (only reachable via direct field mutation)
  /// is clamped back to 1 instead of throwing.
  T? add(T value) {
    if (maxSize < 1) {
      maxSize = 1;
    }
    T? evicted;
    if (_items.length >= maxSize) {
      evicted = _items.removeFirst();
      _droppedCount++;
    }
    _items.addLast(value);
    return evicted;
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
