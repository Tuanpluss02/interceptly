import 'dart:async';
import 'dart:collection';

import '../model/index_entry.dart';
import '../model/http_call_filter.dart';

/// In-memory list of [IndexEntry]s with a broadcast stream for UI updates.
///
/// All mutations happen on the main isolate (after the WriterIsolate sends
/// back a completed [IndexEntry]). No locking needed.
class MemoryIndex {
  MemoryIndex({required this.maxEntries});

  final int maxEntries;
  final List<IndexEntry> _entries = [];
  final StreamController<List<IndexEntry>> _controller =
      StreamController<List<IndexEntry>>.broadcast();

  /// Live stream of all entries — emit on every mutation.
  Stream<List<IndexEntry>> get stream => _controller.stream;

  /// Unmodifiable snapshot of the current entries (newest first).
  List<IndexEntry> get entries => UnmodifiableListView(_entries);

  int get length => _entries.length;

  void add(IndexEntry entry) {
    if (_entries.length >= maxEntries) {
      _entries.removeLast();
    }
    _entries.insert(0, entry);
    _controller.add(UnmodifiableListView(_entries));
  }

  /// Returns entries matching [filter], or all if [filter.isEmpty].
  List<IndexEntry> filtered(HttpCallFilter filter) {
    if (filter.isEmpty) return entries;
    return _entries.where((e) => _matches(e, filter)).toList();
  }

  void clear() {
    _entries.clear();
    _controller.add(UnmodifiableListView(_entries));
  }

  Future<void> dispose() async {
    await _controller.close();
  }

  static bool _matches(IndexEntry e, HttpCallFilter f) {
    final method = f.method?.trim();
    if (method != null && method.isNotEmpty) {
      if (e.method.toUpperCase() != method.toUpperCase()) return false;
    }

    if (f.statusCode != null && e.statusCode != f.statusCode) return false;

    final host = f.host?.trim();
    if (host != null && host.isNotEmpty) {
      final uri = Uri.tryParse(e.url);
      if (uri == null || !uri.host.toLowerCase().contains(host.toLowerCase())) {
        return false;
      }
    }

    final q = f.query?.trim().toLowerCase();
    if (q != null && q.isNotEmpty) {
      if (e.url.toLowerCase().contains(q)) return true;
      if (e.errorMessage?.toLowerCase().contains(q) ?? false) return true;
      return false;
    }

    return true;
  }
}
