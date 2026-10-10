import 'dart:collection';

import '../model/index_entry.dart';
import '../model/request_filter.dart';

/// In-memory list of [IndexEntry]s.
///
/// All mutations happen on the main isolate (after the WriterIsolate sends
/// back a completed [IndexEntry]). No locking needed.
class MemoryIndex {
  MemoryIndex({required this.maxEntries});

  final int maxEntries;
  final List<IndexEntry> _entries = [];
  final Map<String, int> _idIndex = {};

  /// Unmodifiable snapshot of the current entries (newest first).
  List<IndexEntry> get entries => UnmodifiableListView(_entries);

  int get length => _entries.length;

  void add(IndexEntry entry) {
    var existingIndex = _idIndex[entry.id];
    if (existingIndex == null ||
        existingIndex >= _entries.length ||
        _entries[existingIndex].id != entry.id) {
      final idx = _entries.indexWhere((e) => e.id == entry.id);
      if (idx != -1) {
        existingIndex = idx;
        _idIndex[entry.id] = idx;
      } else {
        _idIndex.remove(entry.id);
      }
    }

    if (existingIndex != null &&
        existingIndex < _entries.length &&
        _entries[existingIndex].id == entry.id) {
      _entries[existingIndex] = entry;
      return;
    }

    if (_entries.length >= maxEntries) {
      final removed = _entries.removeLast();
      _idIndex.remove(removed.id);
    }
    _entries.insert(0, entry);
    _idIndex.updateAll((key, val) => val + 1);
    _idIndex[entry.id] = 0;
  }

  /// Returns entries matching [filter], or all entries if [filter.isEmpty].
  List<IndexEntry> filtered(RequestFilter filter) {
    if (filter.isEmpty) return entries;
    return _entries.where(filter.matches).toList();
  }

  void clear() {
    _entries.clear();
    _idIndex.clear();
  }
}
