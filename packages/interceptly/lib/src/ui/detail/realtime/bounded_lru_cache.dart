import 'dart:collection';

/// A bounded Least-Recently-Used (LRU) cache with a fixed maximum [capacity].
///
/// When the cache exceeds [capacity], the least recently accessed item is evicted.
/// Accessing an item via [operator []] or [get] marks it as most recently used.
/// Inserting or updating an item via [operator []=] or [set] marks it as most recently used.
class BoundedLruCache<K, V> with MapMixin<K, V> {
  /// The maximum number of entries allowed in this cache.
  final int capacity;

  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  /// Creates a [BoundedLruCache] with the specified [capacity] (defaults to 30).
  BoundedLruCache({this.capacity = 30})
      : assert(capacity > 0, 'Capacity must be greater than zero');

  @override
  V? operator [](Object? key) {
    if (!_map.containsKey(key)) return null;
    final value = _map.remove(key) as V;
    _map[key as K] = value;
    return value;
  }

  @override
  void operator []=(K key, V value) {
    if (_map.containsKey(key)) {
      _map.remove(key);
    } else if (_map.length >= capacity) {
      _map.remove(_map.keys.first);
    }
    _map[key] = value;
  }

  @override
  void clear() => _map.clear();

  @override
  Iterable<K> get keys => _map.keys;

  @override
  V? remove(Object? key) => _map.remove(key);

  @override
  bool containsKey(Object? key) => _map.containsKey(key);

  @override
  int get length => _map.length;

  /// Retrieves [key] and refreshes its LRU position.
  V? get(K key) => this[key];

  /// Stores [value] at [key], evicting LRU if exceeding [capacity].
  void set(K key, V value) => this[key] = value;
}
