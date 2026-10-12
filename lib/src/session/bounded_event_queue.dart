import 'dart:collection';

class BoundedEventQueue<T> {
  BoundedEventQueue({required this.maxSize})
      : assert(maxSize > 0, 'maxSize must be > 0');

  int maxSize;
  final Queue<T> _items = Queue<T>();
  int _droppedCount = 0;

  /// Changes capacity, counting already-queued overflow as dropped.
  void updateMaxSize(int value) {
    assert(value > 0, 'maxSize must be > 0');
    maxSize = value;
    while (_items.length > maxSize) {
      _items.removeFirst();
      _droppedCount++;
    }
  }

  int get length => _items.length;
  int get droppedCount => _droppedCount;
  bool get isEmpty => _items.isEmpty;

  void add(T value) {
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
