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

  /// Unmodifiable snapshot of the current entries (newest first).
  List<IndexEntry> get entries => UnmodifiableListView(_entries);

  int get length => _entries.length;

  void add(IndexEntry entry) {
    final existingIndex = _entries.indexWhere((e) => e.id == entry.id);
    if (existingIndex != -1) {
      _entries[existingIndex] = entry;
      return;
    }

    if (_entries.length >= maxEntries) {
      _entries.removeLast();
    }
    _entries.insert(0, entry);
  }

  /// Returns entries matching [filter], or all entries if [filter.isEmpty].
  List<IndexEntry> filtered(RequestFilter filter) {
    if (filter.isEmpty) return entries;
    return _entries.where(filter.matches).toList();
  }

  void clear() {
    _entries.clear();
  }
}
