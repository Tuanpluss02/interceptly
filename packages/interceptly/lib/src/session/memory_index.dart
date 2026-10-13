import 'dart:collection';

import '../model/index_entry.dart';
import '../model/request_filter.dart';

/// In-memory fixed-capacity ring buffer of [IndexEntry] items.
///
/// Mutations occur on the main isolate after background processing completes.
class MemoryIndex {
  MemoryIndex({required this.maxEntries})
      : _buffer = List<IndexEntry?>.filled(
          maxEntries > 0 ? maxEntries : 0,
          null,
        );

  int maxEntries;
  List<IndexEntry?> _buffer;
  final Map<String, int> _idIndex = {};

  int _head = 0;
  int _count = 0;

  /// Number of entries currently stored in the buffer.
  int get length => _count;

  /// Live unmodifiable view of entries ordered newest-first.
  ///
  /// This is a live view backed by the ring buffer, not an isolated snapshot.
  /// Do not retain references across mutations to [MemoryIndex].
  List<IndexEntry> get entries {
    if (_count == 0) return const <IndexEntry>[];
    return _RingBufferListView(_buffer, _head, _count, maxEntries);
  }

  /// Looks up an entry by its unique [id] in O(1) time.
  IndexEntry? byId(String id) {
    final slot = _idIndex[id];
    if (slot == null) return null;
    return _buffer[slot];
  }

  /// Alias for [byId] matching interface contract.
  IndexEntry? get(String id) => byId(id);

  /// Inserts a new entry or updates an existing entry in-place in O(1) time.
  void add(IndexEntry entry) {
    if (maxEntries <= 0) {
      throw RangeError.value(
        maxEntries,
        'maxEntries',
        'Must be greater than 0',
      );
    }

    final existingSlot = _idIndex[entry.id];
    if (existingSlot != null) {
      _buffer[existingSlot] = entry;
      return;
    }

    if (_count >= maxEntries) {
      final oldest = _buffer[_head]!;
      _idIndex.remove(oldest.id);
      _buffer[_head] = entry;
      _idIndex[entry.id] = _head;
      _head = (_head + 1) % maxEntries;
    } else {
      final slot = (_head + _count) % maxEntries;
      _buffer[slot] = entry;
      _idIndex[entry.id] = slot;
      _count++;
    }
  }

  /// Returns entries matching [filter], or all entries if [filter.isEmpty].
  List<IndexEntry> filtered(RequestFilter filter) {
    if (filter.isEmpty) return entries;
    return entries.where(filter.matches).toList();
  }

  /// Clears all entries and resets the ring buffer state.
  void clear() {
    _buffer.fillRange(0, _buffer.length, null);
    _head = 0;
    _count = 0;
    _idIndex.clear();
  }

  /// Changes capacity, keeping the newest entries when shrinking.
  void updateMaxEntries(int value) {
    if (value == maxEntries) return;
    final retained = value <= 0 ? <IndexEntry>[] : entries.take(value).toList();
    maxEntries = value;
    _buffer = List<IndexEntry?>.filled(value > 0 ? value : 0, null);
    _head = 0;
    _count = 0;
    _idIndex.clear();
    for (var i = retained.length - 1; i >= 0; i--) {
      add(retained[i]);
    }
  }
}

/// Unmodifiable, reverse-indexed List view over a ring buffer.
class _RingBufferListView extends ListBase<IndexEntry> {
  _RingBufferListView(this._buffer, this._head, this._count, this._capacity);

  final List<IndexEntry?> _buffer;
  final int _head;
  final int _count;
  final int _capacity;

  @override
  int get length => _count;

  @override
  set length(int newLength) =>
      throw UnsupportedError('Cannot modify an unmodifiable list view');

  @override
  IndexEntry operator [](int index) {
    RangeError.checkValidIndex(index, this, null, _count);
    final slot = (_head + _count - 1 - index) % _capacity;
    return _buffer[slot]!;
  }

  @override
  void operator []=(int index, IndexEntry value) =>
      throw UnsupportedError('Cannot modify an unmodifiable list view');
}
