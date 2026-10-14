import 'dart:collection';

/// A fixed-capacity FIFO circular ring buffer.
///
/// When the buffer reaches [capacity], adding a new item automatically evicts
/// the oldest item.
///
/// Capacities below 1 are clamped to 1 so misconfiguration degrades to a
/// single-slot buffer instead of crashing.
class RingBuffer<T> {
  RingBuffer({required int capacity})
      : capacity = capacity < 1 ? 1 : capacity,
        _items = ListQueue<T>();

  /// Maximum number of items this buffer can hold before evicting the oldest.
  int capacity;

  final ListQueue<T> _items;
  int _droppedCount = 0;

  /// Current number of items in the buffer.
  int get length => _items.length;

  /// Total number of items evicted due to buffer capacity overflow.
  int get droppedCount => _droppedCount;

  /// True if buffer has no items.
  bool get isEmpty => _items.isEmpty;

  /// True if buffer has at least one item.
  bool get isNotEmpty => _items.isNotEmpty;

  /// Appends [item] to the end of the buffer. If [length] equals [capacity],
  /// the oldest item is evicted first.
  void add(T item) {
    if (capacity <= 0) return;
    if (_items.length >= capacity) {
      _items.removeFirst();
      _droppedCount++;
    }
    _items.addLast(item);
  }

  /// Updates capacity, evicting the oldest items if shrinking below current size.
  ///
  /// Values below 1 are clamped to 1 instead of throwing.
  void updateCapacity(int newCapacity) {
    capacity = newCapacity < 1 ? 1 : newCapacity;
    while (_items.length > capacity) {
      _items.removeFirst();
      _droppedCount++;
    }
  }

  /// Returns an unmodifiable list of elements in FIFO order (oldest to newest).
  List<T> toList() => List<T>.unmodifiable(_items);

  /// Accesses element at [index] (0 being oldest retained element).
  T operator [](int index) {
    RangeError.checkValidIndex(index, _items, null, _items.length);
    return _items.elementAt(index);
  }

  /// Wipes all items and resets dropped counter.
  void clear() {
    _items.clear();
    _droppedCount = 0;
  }
}
