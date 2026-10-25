import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../engine/body_decode_service.dart';
import '../../engine/search_service.dart';
import '../../model/body_location.dart';
import '../../model/index_entry.dart';
import '../../model/search_match_scope.dart';

/// Lightweight UI ViewModel managing progressive master search over captured entries.
///
/// Delegates search execution to [SearchService] and handles UI notification throttling,
/// dynamic entry updates, and search lifecycle state.
class MasterSearchController extends ChangeNotifier {
  String? _query;
  List<IndexEntry>? _results;
  final Set<String> _matchedIds = {};
  final Map<String, Set<SearchMatchScope>> _matchScopes = {};
  final Map<String, IndexEntry> _pendingAsyncEntries = {};
  Set<String>? _activeSnapshotIds;
  bool _isScanningBodies = false;
  bool _isScanningFiles = false;
  int _generation = 0;
  Timer? _throttleTimer;
  bool _isDisposed = false;

  /// Number of entries currently awaiting asynchronous inline body matching.
  @visibleForTesting
  int get pendingAsyncEntryCount => _pendingAsyncEntries.length;

  /// The active search query, or `null` if search is inactive.
  String? get query => _query;

  /// Progressive matching results, or `null` if search is inactive.
  List<IndexEntry>? get results => _results;

  /// Whether a search is currently active.
  bool get isActive => _query != null;

  /// Whether the controller is actively scanning in-memory request/response bodies.
  bool get isScanningBodies => _isScanningBodies;

  /// Whether the controller is actively scanning file-backed bodies on disk.
  bool get isScanningFiles => _isScanningFiles;

  /// Returns the matched scopes (e.g. url, headers, body, error) for entry [id].
  Set<SearchMatchScope> getScopes(String id) =>
      _matchScopes[id] ?? const <SearchMatchScope>{};

  void _notifyThrottled({bool force = false}) {
    if (_isDisposed) return;
    if (force) {
      _throttleTimer?.cancel();
      _throttleTimer = null;
      notifyListeners();
      return;
    }
    if (_throttleTimer?.isActive ?? false) return;
    _throttleTimer = Timer(const Duration(milliseconds: 150), () {
      _throttleTimer = null;
      if (!_isDisposed) {
        notifyListeners();
      }
    });
  }

  /// Cancels any in-progress search and clears results.
  void cancel() {
    _generation++;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _query = null;
    _results = null;
    _matchedIds.clear();
    _matchScopes.clear();
    _pendingAsyncEntries.clear();
    _activeSnapshotIds = null;
    _isScanningBodies = false;
    _isScanningFiles = false;
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// Resets search state without notifying — used during session clear.
  void reset() {
    _generation++;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _query = null;
    _results = null;
    _matchedIds.clear();
    _matchScopes.clear();
    _pendingAsyncEntries.clear();
    _activeSnapshotIds = null;
    _isScanningBodies = false;
    _isScanningFiles = false;
  }

  /// Starts a progressive search over [allEntries].
  ///
  /// [filePath] is the temp file path for file-backed bodies; pass `null` to
  /// skip Phase 3.
  Future<void> start({
    required String query,
    required List<IndexEntry> allEntries,
    required String? filePath,
    int? currentFileRotationCount,
  }) async {
    if (_isDisposed) return;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      cancel();
      return;
    }

    final gen = ++_generation;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    final entriesSnapshot = List<IndexEntry>.from(allEntries);

    _query = trimmed;
    _results = [];
    _matchedIds.clear();
    _matchScopes.clear();
    _pendingAsyncEntries.clear();
    _activeSnapshotIds = {for (final e in entriesSnapshot) e.id};
    _isScanningBodies = false;
    _isScanningFiles = false;
    _notifyThrottled(force: true);

    try {
      await SearchService.search(
        entries: entriesSnapshot,
        query: trimmed,
        filePath: filePath,
        fileRotationCount: currentFileRotationCount,
        onPhaseChange: (phase) {
          if (gen != _generation || _isDisposed) return;
          switch (phase) {
            case SearchPhase.metadata:
              _isScanningBodies = false;
              _isScanningFiles = false;
              break;
            case SearchPhase.inMemoryBodies:
              _isScanningBodies = true;
              _isScanningFiles = false;
              _notifyThrottled(force: true);
              break;
            case SearchPhase.fileBodies:
              _isScanningBodies = false;
              _isScanningFiles = true;
              _notifyThrottled(force: true);
              break;
            case SearchPhase.done:
              _isScanningBodies = false;
              _isScanningFiles = false;
              break;
          }
        },
        onProgress: (progressiveResults, {required bool isDone}) {
          if (gen != _generation || _isDisposed) return;
          final snapshotIds = _activeSnapshotIds;
          final updatedList = <IndexEntry>[];
          final seenIds = <String>{};

          // Preserve dynamically added/updated entries that occurred after start() snapshot
          if (_results != null && snapshotIds != null) {
            for (final existing in _results!) {
              final id = existing.id;
              if (!snapshotIds.contains(id) && _matchedIds.contains(id)) {
                updatedList.add(existing);
                seenIds.add(id);
              }
            }
          }

          for (final res in progressiveResults) {
            if (res.summary case final IndexEntry entry) {
              final id = entry.id;
              if (snapshotIds != null && !snapshotIds.contains(id)) {
                continue;
              }
              updatedList.add(entry);
              seenIds.add(id);
              _matchedIds.add(id);
              _matchScopes[id] = Set<SearchMatchScope>.from(res.matchScopes);
            }
          }

          _matchedIds.removeWhere((id) => !seenIds.contains(id));
          _matchScopes.removeWhere((id, _) => !seenIds.contains(id));
          _results = updatedList;
          _notifyThrottled(force: isDone);
        },
        isCancelled: () => gen != _generation || _isDisposed,
      );
    } finally {
      if (gen == _generation && !_isDisposed) {
        _activeSnapshotIds = null;
        _isScanningBodies = false;
        _isScanningFiles = false;
      }
    }
  }

  /// Dynamically updates or inserts [entry] in search results if an active query matches.
  void updateOrAddEntry(IndexEntry entry) {
    final query = _query;
    if (_isDisposed || query == null || query.isEmpty || _results == null) {
      return;
    }

    _activeSnapshotIds?.remove(entry.id);

    final inlineBytes = (entry.inlineRequestBody?.length ?? 0) +
        (entry.inlineResponseBody?.length ?? 0);
    final offloadInline = entry.bodyLocation == BodyLocation.memory &&
        inlineBytes > BodyDecodeService.computeThreshold;

    if (offloadInline) {
      _pendingAsyncEntries[entry.id] = entry;
    } else {
      _pendingAsyncEntries.remove(entry.id);
    }

    final matchResult = SearchService.matchEntry(
      entry,
      query,
      searchBody: !offloadInline,
    );
    final scopes = matchResult != null
        ? Set<SearchMatchScope>.from(matchResult.matchScopes)
        : <SearchMatchScope>{};

    final existingScopes = _matchScopes[entry.id];
    if (existingScopes != null &&
        existingScopes.contains(SearchMatchScope.body) &&
        entry.bodyLocation == BodyLocation.file) {
      scopes.add(SearchMatchScope.body);
    }

    final isExisting = _matchedIds.contains(entry.id);

    if (scopes.isNotEmpty) {
      if (isExisting) {
        final existingIndex = _results!.indexWhere((e) => e.id == entry.id);
        if (existingIndex >= 0) {
          _results![existingIndex] = entry;
        } else {
          _results!.insert(0, entry);
        }
      } else {
        _results!.insert(0, entry);
        _matchedIds.add(entry.id);
      }
      _matchScopes[entry.id] = scopes;
      _notifyThrottled();
    } else if (!offloadInline) {
      if (isExisting) {
        _results!.removeWhere((e) => e.id == entry.id);
        _matchedIds.remove(entry.id);
        _matchScopes.remove(entry.id);
        _notifyThrottled();
      }
    } else if (isExisting) {
      final existingIndex = _results!.indexWhere((e) => e.id == entry.id);
      if (existingIndex >= 0) {
        _results![existingIndex] = entry;
      }
    }

    if (offloadInline) {
      final gen = _generation;
      final queryLower = query.trim().toLowerCase();
      unawaited(
        SearchService.matchInlineBodyAsync(entry, queryLower).then((matched) {
          if (_isDisposed ||
              gen != _generation ||
              _results == null ||
              !identical(_pendingAsyncEntries[entry.id], entry)) {
            return;
          }
          _pendingAsyncEntries.remove(entry.id);
          final currentlyExisting = _matchedIds.contains(entry.id);
          if (matched) {
            if (currentlyExisting) {
              final idx = _results!.indexWhere((e) => e.id == entry.id);
              if (idx >= 0) {
                _results![idx] = entry;
              } else {
                _results!.insert(0, entry);
              }
            } else {
              _results!.insert(0, entry);
              _matchedIds.add(entry.id);
            }
            (_matchScopes[entry.id] ??= <SearchMatchScope>{})
                .add(SearchMatchScope.body);
            _notifyThrottled();
          } else if (scopes.isEmpty && currentlyExisting) {
            _results!.removeWhere((e) => e.id == entry.id);
            _matchedIds.remove(entry.id);
            _matchScopes.remove(entry.id);
            _notifyThrottled();
          }
        }),
      );
    }
  }

  /// Records a file-backed body match for testing purposes.
  @visibleForTesting
  void recordFileMatchForTesting(IndexEntry entry) {
    if (_results == null) return;
    if (!_matchedIds.contains(entry.id)) {
      _matchedIds.add(entry.id);
      _results!.insert(0, entry);
    }
    (_matchScopes[entry.id] ??= <SearchMatchScope>{})
        .add(SearchMatchScope.body);
  }

  /// Prunes any search results whose IDs are not present in [validIds].
  void pruneMissing(Set<String> validIds) {
    if (_isDisposed || _results == null) return;

    _pendingAsyncEntries.removeWhere((id, _) => !validIds.contains(id));
    _activeSnapshotIds?.removeWhere((id) => !validIds.contains(id));

    if (_matchedIds.isEmpty) return;
    final hasMissing = _matchedIds.any((id) => !validIds.contains(id));
    if (!hasMissing) return;

    var removed = false;
    for (var i = _results!.length - 1; i >= 0; i--) {
      final id = _results![i].id;
      if (!validIds.contains(id)) {
        _results!.removeAt(i);
        _matchedIds.remove(id);
        _matchScopes.remove(id);
        removed = true;
      }
    }
    if (removed) {
      _notifyThrottled();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _generation++;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    super.dispose();
  }
}
