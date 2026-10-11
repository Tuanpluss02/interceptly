import 'dart:async';
import 'dart:io';

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
  Timer? _throttleTimer;
  bool _isDisposed = false;

  String? get query => _query;
  List<IndexEntry>? get results => _results;
  bool get isActive => _query != null;
  bool get isScanningBodies => _isScanningBodies;
  bool get isScanningFiles => _isScanningFiles;

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
    _isScanningBodies = false;
    _isScanningFiles = false;
    _notifyThrottled(force: true);

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

    for (var i = 0; i < entriesSnapshot.length; i++) {
      if (gen != _generation || _isDisposed) return;
      final e = entriesSnapshot[i];
      if (matchesStructured(e)) {
        matchedIds.add(e.id);
        _results?.add(e);
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
      if (e.bodyLocation == BodyLocation.memory &&
          !matchedIds.contains(e.id) &&
          matchesInlineBody(e)) {
        matchedIds.add(e.id);
        _results?.add(e);
        _notifyThrottled();
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
        if (e.bodyLocation == BodyLocation.file &&
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
          const batchSize = 4;
          for (var start = 0; start < fileEntries.length; start += batchSize) {
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
                final raw = await BodyStore.readWithHandle(raf, offset, length);
                batchPayloads.add((e, raw));
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('[Interceptly] master search file read error: $e');
                }
                batchPayloads.add(null);
              }
            }

            final futures = batchPayloads.map((payload) async {
              if (payload == null) return (false, null);
              final (e, raw) = payload;
              try {
                final decoded = raw.length > BodyDecodeService.computeThreshold
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
              if (matched && e != null && !matchedIds.contains(e.id)) {
                matchedIds.add(e.id);
                _results?.add(e);
                hasNewMatch = true;
              }
            }
            if (hasNewMatch) {
              _notifyThrottled();
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

  @override
  void dispose() {
    _isDisposed = true;
    _generation++;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    super.dispose();
  }
}
