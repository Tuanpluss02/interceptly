import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../model/body_location.dart';
import '../model/index_entry.dart';
import '../model/search_match_scope.dart';
import 'body_decode_service.dart';
import 'body_store.dart';

/// Manages the 3-phase progressive master search over captured entries.
///
/// - Phase 1 (sync): URL, method, headers, error message.
/// - Phase 2 (chunked async): in-memory body bytes.
/// - Phase 3 (async I/O): file-backed body bytes.
///
/// Callers listen to this [ChangeNotifier] to rebuild when results change.
class MasterSearchController extends ChangeNotifier {
  String? _query;
  List<IndexEntry>? _results;
  final Map<String, Set<SearchMatchScope>> _matchScopes = {};
  bool _isScanningBodies = false;
  bool _isScanningFiles = false;
  int _generation = 0;
  Timer? _throttleTimer;
  bool _isDisposed = false;

  String? get query => _query;
  List<IndexEntry>? get results => _results;
  bool get isActive => _query != null;
  bool get isScanningBodies => _isScanningBodies;
  bool get isScanningFiles => _isScanningFiles;

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
    final q = trimmed.toLowerCase();
    final entriesSnapshot = List<IndexEntry>.from(allEntries);

    _query = trimmed;
    _results = [];
    _matchScopes.clear();
    _isScanningBodies = false;
    _isScanningFiles = false;
    _notifyThrottled(force: true);

    final matchedIds = <String>{};

    for (var i = 0; i < entriesSnapshot.length; i++) {
      if (gen != _generation || _isDisposed) return;
      final e = entriesSnapshot[i];
      final scopes = _checkStructuredScopes(e, q);
      if (scopes.isNotEmpty) {
        matchedIds.add(e.id);
        _results?.add(e);
        _matchScopes[e.id] = scopes;
      }
      if (i % 50 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (gen != _generation || _isDisposed) return;
    _notifyThrottled(force: true);

    _isScanningBodies = true;
    _notifyThrottled(force: true);
    for (var i = 0; i < entriesSnapshot.length; i++) {
      if (gen != _generation || _isDisposed) return;
      final e = entriesSnapshot[i];
      if (e.bodyLocation == BodyLocation.memory && _matchesInlineBody(e, q)) {
        if (!matchedIds.contains(e.id)) {
          matchedIds.add(e.id);
          _results?.add(e);
          _matchScopes[e.id] = {SearchMatchScope.body};
          _notifyThrottled();
        } else {
          _matchScopes[e.id]?.add(SearchMatchScope.body);
        }
      }
      if (i % 20 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (gen != _generation || _isDisposed) return;
    _isScanningBodies = false;
    _notifyThrottled(force: true);

    if (filePath != null) {
      _isScanningFiles = true;
      _notifyThrottled(force: true);

      final fileEntries = <(IndexEntry, int, int)>[];
      for (final e in entriesSnapshot) {
        final isExpiredByRotation = currentFileRotationCount != null &&
            e.fileRotationCount != null &&
            e.fileRotationCount! < currentFileRotationCount;
        if (!isExpiredByRotation &&
            e.bodyLocation == BodyLocation.file &&
            !matchedIds.contains(e.id) &&
            e.fileOffset != null &&
            e.fileLength != null) {
          fileEntries.add((e, e.fileOffset!, e.fileLength!));
        }
      }

      if (fileEntries.isNotEmpty) {
        RandomAccessFile? raf;
        try {
          raf = await BodyStore.openReadHandle(filePath);
          if (fileEntries.length <= 8) {
            var hasNewMatch = false;
            for (final (e, offset, length) in fileEntries) {
              if (gen != _generation || _isDisposed) return;
              try {
                final raw = await BodyStore.readWithHandle(raf, offset, length);
                final decoded = BodyDecodeService.unpackToText(raw);
                final combined =
                    '${decoded.$1 ?? ''}\n${decoded.$2 ?? ''}'.toLowerCase();
                if (combined.contains(q)) {
                  if (!matchedIds.contains(e.id)) {
                    matchedIds.add(e.id);
                    _results?.add(e);
                    hasNewMatch = true;
                  }
                  (_matchScopes[e.id] ??= <SearchMatchScope>{})
                      .add(SearchMatchScope.body);
                }
              } catch (_) {}
            }
            if (hasNewMatch) {
              _notifyThrottled();
            }
          } else {
            final batchSize = fileEntries.length > 100 ? 32 : 16;
            for (var start = 0;
                start < fileEntries.length;
                start += batchSize) {
              if (gen != _generation || _isDisposed) return;
              final batch = fileEntries.sublist(
                start,
                (start + batchSize).clamp(0, fileEntries.length),
              );

              final batchPayloads = <(IndexEntry, Uint8List)?>[];
              for (final item in batch) {
                if (gen != _generation || _isDisposed) return;
                try {
                  final (e, offset, length) = item;
                  final raw =
                      await BodyStore.readWithHandle(raf, offset, length);
                  batchPayloads.add((e, raw));
                } catch (e) {
                  if (kDebugMode) {
                    debugPrint(
                        '[Interceptly] master search file read error: $e');
                  }
                  batchPayloads.add(null);
                }
              }

              final futures = batchPayloads.map((payload) async {
                if (payload == null) return (false, null);
                final (e, raw) = payload;
                try {
                  final decoded =
                      raw.length > BodyDecodeService.computeThreshold
                          ? await compute(BodyDecodeService.unpackToText, raw)
                          : BodyDecodeService.unpackToText(raw);
                  final combined =
                      '${decoded.$1 ?? ''}\n${decoded.$2 ?? ''}'.toLowerCase();
                  if (combined.contains(q)) return (true, e);
                } catch (e) {
                  if (kDebugMode) {
                    debugPrint('[Interceptly] master search decode error: $e');
                  }
                }
                return (false, null);
              });

              final results = await Future.wait(futures);
              if (gen != _generation || _isDisposed) return;
              var hasNewMatch = false;
              for (final (matched, e) in results) {
                if (matched && e != null) {
                  if (!matchedIds.contains(e.id)) {
                    matchedIds.add(e.id);
                    _results?.add(e);
                    hasNewMatch = true;
                  }
                  (_matchScopes[e.id] ??= <SearchMatchScope>{})
                      .add(SearchMatchScope.body);
                }
              }
              if (hasNewMatch) {
                _notifyThrottled();
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[Interceptly] master search file read error: $e');
          }
        } finally {
          await raf?.close();
        }
      }

      if (gen != _generation || _isDisposed) return;
      _isScanningFiles = false;
      _notifyThrottled(force: true);
    }
  }

  /// Dynamically updates or inserts [entry] in search results if an active query matches.
  void updateOrAddEntry(IndexEntry entry) {
    final query = _query;
    if (_isDisposed || query == null || query.isEmpty || _results == null) {
      return;
    }

    final q = query.toLowerCase();
    final scopes = _checkStructuredScopes(entry, q);
    if (scopes.isEmpty &&
        entry.bodyLocation == BodyLocation.memory &&
        _matchesInlineBody(entry, q)) {
      scopes.add(SearchMatchScope.body);
    }

    final existingIndex = _results!.indexWhere((e) => e.id == entry.id);

    if (scopes.isNotEmpty) {
      if (existingIndex >= 0) {
        _results![existingIndex] = entry;
      } else {
        _results!.insert(0, entry);
      }
      _matchScopes[entry.id] = scopes;
      _notifyThrottled();
    } else {
      if (existingIndex >= 0) {
        _results!.removeAt(existingIndex);
        _matchScopes.remove(entry.id);
        _notifyThrottled();
      }
    }
  }

  /// Prunes any search results whose IDs are not present in [validIds].
  void pruneMissing(Set<String> validIds) {
    if (_isDisposed || _results == null) return;
    var removed = false;
    for (var i = _results!.length - 1; i >= 0; i--) {
      final id = _results![i].id;
      if (!validIds.contains(id)) {
        _results!.removeAt(i);
        _matchScopes.remove(id);
        removed = true;
      }
    }
    if (removed) {
      _notifyThrottled();
    }
  }

  static Set<SearchMatchScope> _checkStructuredScopes(IndexEntry e, String q) {
    final scopes = <SearchMatchScope>{};
    if (e.url.toLowerCase().contains(q) || e.method.toLowerCase().contains(q)) {
      scopes.add(SearchMatchScope.url);
    }
    if (e.errorMessage?.toLowerCase().contains(q) ?? false) {
      scopes.add(SearchMatchScope.error);
    }
    for (final h in e.requestHeaders.entries) {
      if (h.key.toLowerCase().contains(q) ||
          h.value.toLowerCase().contains(q)) {
        scopes.add(SearchMatchScope.headers);
        break;
      }
    }
    if (!scopes.contains(SearchMatchScope.headers)) {
      for (final h in e.responseHeaders.entries) {
        if (h.key.toLowerCase().contains(q) ||
            h.value.toLowerCase().contains(q)) {
          scopes.add(SearchMatchScope.headers);
          break;
        }
      }
    }
    return scopes;
  }

  static bool _matchesInlineBody(IndexEntry e, String q) {
    final req = BodyDecodeService.decode(
      e.inlineRequestBody,
      e.requestContentType,
    )?.toLowerCase();
    if (req != null && req.contains(q)) return true;
    final res = BodyDecodeService.decode(
      e.inlineResponseBody,
      e.responseContentType,
    )?.toLowerCase();
    return res != null && res.contains(q);
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
