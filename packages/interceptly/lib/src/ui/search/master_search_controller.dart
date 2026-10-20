import 'dart:async';

import 'package:flutter/foundation.dart';

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
  bool _isScanningBodies = false;
  bool _isScanningFiles = false;
  int _generation = 0;
  Timer? _throttleTimer;
  bool _isDisposed = false;

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
          final updatedList = <IndexEntry>[];
          _matchedIds.clear();
          _matchScopes.clear();
          for (final res in progressiveResults) {
            if (res.summary case final IndexEntry entry) {
              updatedList.add(entry);
              _matchedIds.add(entry.id);
              _matchScopes[entry.id] =
                  Set<SearchMatchScope>.from(res.matchScopes);
            }
          }
          _results = updatedList;
          _notifyThrottled(force: isDone);
        },
        isCancelled: () => gen != _generation || _isDisposed,
      );
    } finally {
      if (gen == _generation && !_isDisposed) {
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

    final matchResult = SearchService.matchEntry(entry, query);
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
    } else {
      if (isExisting) {
        _results!.removeWhere((e) => e.id == entry.id);
        _matchedIds.remove(entry.id);
        _matchScopes.remove(entry.id);
        _notifyThrottled();
      }
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
    if (_isDisposed || _results == null || _matchedIds.isEmpty) return;
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
