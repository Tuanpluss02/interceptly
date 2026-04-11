import 'package:flutter/foundation.dart';

import '../model/body_location.dart';
import '../model/index_entry.dart';
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
  bool _isScanningBodies = false;
  bool _isScanningFiles = false;
  int _generation = 0;

  String? get query => _query;
  List<IndexEntry>? get results => _results;
  bool get isActive => _query != null;
  bool get isScanningBodies => _isScanningBodies;
  bool get isScanningFiles => _isScanningFiles;

  /// Cancels any in-progress search and clears results.
  void cancel() {
    _generation++;
    _query = null;
    _results = null;
    _isScanningBodies = false;
    _isScanningFiles = false;
    notifyListeners();
  }

  /// Resets search state without notifying — used during session clear.
  void reset() {
    _generation++;
    _query = null;
    _results = null;
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
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      cancel();
      return;
    }

    final gen = ++_generation;
    final q = trimmed.toLowerCase();

    _query = trimmed;
    _results = [];
    _isScanningBodies = false;
    _isScanningFiles = false;
    notifyListeners();

    final matchedIds = <String>{};

    bool matchesStructured(IndexEntry e) {
      if (e.url.toLowerCase().contains(q)) return true;
      if (e.method.toLowerCase().contains(q)) return true;
      if (e.errorMessage?.toLowerCase().contains(q) ?? false) return true;
      for (final h in e.requestHeaders.entries) {
        if (h.key.toLowerCase().contains(q)) return true;
        if (h.value.toLowerCase().contains(q)) return true;
      }
      for (final h in e.responseHeaders.entries) {
        if (h.key.toLowerCase().contains(q)) return true;
        if (h.value.toLowerCase().contains(q)) return true;
      }
      return false;
    }

    bool matchesInlineBody(IndexEntry e) {
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

    // Phase 1: structured fields (sync).
    for (final e in allEntries) {
      if (matchesStructured(e)) {
        matchedIds.add(e.id);
        _results!.add(e);
      }
    }
    if (gen != _generation) return;
    notifyListeners();

    // Phase 2: in-memory bodies in small async batches.
    _isScanningBodies = true;
    notifyListeners();
    for (var i = 0; i < allEntries.length; i++) {
      if (gen != _generation) return;
      final e = allEntries[i];
      if (e.bodyLocation == BodyLocation.memory &&
          !matchedIds.contains(e.id) &&
          matchesInlineBody(e)) {
        matchedIds.add(e.id);
        _results!.add(e);
      }
      if (i % 20 == 0) {
        notifyListeners();
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (gen != _generation) return;
    _isScanningBodies = false;
    notifyListeners();

    // Phase 3: file-backed bodies in parallel batches of 4.
    if (filePath != null) {
      _isScanningFiles = true;
      notifyListeners();

      final fileEntries = <(IndexEntry, int, int)>[];
      for (final e in allEntries) {
        if (e.bodyLocation == BodyLocation.file &&
            !matchedIds.contains(e.id) &&
            e.fileOffset != null &&
            e.fileLength != null) {
          fileEntries.add((e, e.fileOffset!, e.fileLength!));
        }
      }

      const batchSize = 4;
      for (var start = 0; start < fileEntries.length; start += batchSize) {
        if (gen != _generation) return;
        final batch = fileEntries.sublist(
          start,
          (start + batchSize).clamp(0, fileEntries.length),
        );

        final futures = batch.map((item) async {
          try {
            final (e, offset, length) = item;
            final raw = await BodyStore.readBytes(filePath, offset, length);
            final decoded = raw.length > BodyDecodeService.computeThreshold
                ? await compute(BodyDecodeService.unpackToText, raw)
                : BodyDecodeService.unpackToText(raw);
            final combined =
                '${decoded.$1 ?? ''}\n${decoded.$2 ?? ''}'.toLowerCase();
            if (combined.contains(q)) return (true, e);
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[Interceptly] master search file read error: $e');
            }
          }
          return (false, null);
        });

        final results = await Future.wait(futures);
        for (final (matched, e) in results) {
          if (matched && e != null && !matchedIds.contains(e.id)) {
            matchedIds.add(e.id);
            _results!.add(e);
            notifyListeners();
          }
        }
      }

      if (gen != _generation) return;
      _isScanningFiles = false;
      notifyListeners();
    }
  }
}
