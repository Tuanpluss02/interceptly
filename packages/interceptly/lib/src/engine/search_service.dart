import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../model/body_location.dart';
import '../model/index_entry.dart';
import '../model/request_summary.dart';
import '../model/search_match_scope.dart';
import '../model/search_result.dart';
import 'body_decode_service.dart';
import 'body_store.dart';

/// Progressive phases of the unified search pipeline.
enum SearchPhase {
  metadata,
  inMemoryBodies,
  fileBodies,
  done,
}

/// Unified, self-contained search engine encapsulating multi-phase progressive search,
/// structured metadata matching, binary guards, and batched disk I/O with isolate offloading.
abstract final class SearchService {
  /// Executes a multi-phase progressive search over [entries].
  ///
  /// - Phase 1: Structured metadata matching (URL, method, headers, error details).
  /// - Phase 2: In-memory request and response body decoding.
  /// - Phase 3: Batched file-backed body reads with isolate offloading.
  ///
  /// Callers may supply [onProgress] to receive progressive result updates,
  /// [onPhaseChange] to track the active scanning phase, and [isCancelled]
  /// to abort promptly without leaking resources.
  static Future<List<SearchResult>> search({
    required List<IndexEntry> entries,
    required String query,
    String? filePath,
    int? fileRotationCount,
    bool searchBody = true,
    int? limit,
    String? sinceId,
    String statusFilter = 'all',
    void Function(List<SearchResult> progressiveResults,
            {required bool isDone})?
        onProgress,
    void Function(SearchPhase phase)? onPhaseChange,
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() ?? false) return const [];

    final trimmed = query.trim();
    if (trimmed.isEmpty || entries.isEmpty) {
      onPhaseChange?.call(SearchPhase.done);
      onProgress?.call(const [], isDone: true);
      return const [];
    }

    if (limit != null && limit <= 0) {
      onPhaseChange?.call(SearchPhase.done);
      onProgress?.call(const [], isDone: true);
      return const [];
    }

    final q = trimmed.toLowerCase();

    var candidates = entries;
    if (sinceId != null && sinceId.isNotEmpty) {
      final index = candidates.indexWhere((e) => e.id == sinceId);
      if (index > 0) {
        candidates = candidates.sublist(0, index);
      } else if (index == 0) {
        onPhaseChange?.call(SearchPhase.done);
        onProgress?.call(const [], isDone: true);
        return const [];
      }
    }

    final normalizedStatus = statusFilter.toLowerCase();
    if (normalizedStatus != 'all') {
      candidates = candidates.where((e) {
        final code = e.statusCode;
        return switch (normalizedStatus) {
          'failed' => e.hasError || code >= 400,
          '2xx' => code >= 200 && code < 300,
          '3xx' => code >= 300 && code < 400,
          '4xx' => code >= 400 && code < 500,
          '5xx' => code >= 500 && code < 600,
          _ => true,
        };
      }).toList();
    }

    if (candidates.isEmpty) {
      onPhaseChange?.call(SearchPhase.done);
      onProgress?.call(const [], isDone: true);
      return const [];
    }

    if (isCancelled?.call() ?? false) return const [];

    final results = <SearchResult>[];
    final matchedIds = <String>{};
    final resultIndexMap = <String, int>{};

    onPhaseChange?.call(SearchPhase.metadata);
    for (var i = 0; i < candidates.length; i++) {
      if (isCancelled?.call() ?? false) return const [];
      if (limit != null && results.length >= limit) break;

      final e = candidates[i];
      final scopes = matchStructured(e, q);
      if (scopes.isNotEmpty) {
        matchedIds.add(e.id);
        final item = SearchResult(summary: e, matchScopes: scopes);
        results.add(item);
        resultIndexMap[e.id] = results.length - 1;
      }

      if (i > 0 && i % 50 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (results.isNotEmpty && onProgress != null) {
      onProgress(List.unmodifiable(results), isDone: false);
    }

    if (!searchBody || (limit != null && results.length >= limit)) {
      if (isCancelled?.call() ?? false) return const [];
      onPhaseChange?.call(SearchPhase.done);
      onProgress?.call(List.unmodifiable(results), isDone: true);
      return results;
    }

    if (isCancelled?.call() ?? false) return const [];

    onPhaseChange?.call(SearchPhase.inMemoryBodies);
    var hasNewMatchInPhase2 = false;
    var inlineBytesSinceYield = 0;
    for (var i = 0; i < candidates.length; i++) {
      if (isCancelled?.call() ?? false) return const [];
      if (limit != null && results.length >= limit) break;

      final e = candidates[i];
      if (e.bodyLocation != BodyLocation.memory) continue;

      if (_isBinaryOrEmpty(e)) continue;

      final entryInlineBytes = (e.inlineRequestBody?.length ?? 0) +
          (e.inlineResponseBody?.length ?? 0);
      final matched = await matchInlineBodyAsync(e, q);
      if (isCancelled?.call() ?? false) return const [];

      if (matched) {
        if (resultIndexMap.containsKey(e.id)) {
          final idx = resultIndexMap[e.id]!;
          results[idx] = SearchResult(
            summary: e,
            matchScopes: {...results[idx].matchScopes, SearchMatchScope.body},
          );
        } else {
          matchedIds.add(e.id);
          final item = SearchResult(
            summary: e,
            matchScopes: const {SearchMatchScope.body},
          );
          results.add(item);
          resultIndexMap[e.id] = results.length - 1;
          hasNewMatchInPhase2 = true;
        }
      }

      inlineBytesSinceYield += entryInlineBytes;
      if ((i > 0 && i % 50 == 0) ||
          inlineBytesSinceYield >= BodyDecodeService.computeThreshold) {
        inlineBytesSinceYield = 0;
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (hasNewMatchInPhase2 && onProgress != null) {
      onProgress(List.unmodifiable(results), isDone: false);
    }

    if (limit != null && results.length >= limit) {
      if (isCancelled?.call() ?? false) return const [];
      onPhaseChange?.call(SearchPhase.done);
      onProgress?.call(List.unmodifiable(results), isDone: true);
      return results;
    }

    if (isCancelled?.call() ?? false) return const [];

    if (filePath != null) {
      onPhaseChange?.call(SearchPhase.fileBodies);

      final fileCandidates = <IndexEntry>[];
      for (final e in candidates) {
        final isExpiredByRotation = fileRotationCount != null &&
            e.fileRotationCount != null &&
            e.fileRotationCount! < fileRotationCount;
        if (!isExpiredByRotation &&
            e.bodyLocation == BodyLocation.file &&
            !matchedIds.contains(e.id) &&
            e.fileOffset != null &&
            e.fileLength != null &&
            e.fileLength! > 0 &&
            !_isBinaryOrEmpty(e)) {
          fileCandidates.add(e);
        }
      }

      if (fileCandidates.isNotEmpty) {
        RandomAccessFile? raf;
        try {
          raf = await BodyStore.openReadHandle(filePath);
          final batchSize = fileCandidates.length > 100 ? 32 : 16;
          for (var start = 0;
              start < fileCandidates.length;
              start += batchSize) {
            if (isCancelled?.call() ?? false) break;
            if (limit != null && results.length >= limit) break;

            final batch = fileCandidates.sublist(
              start,
              (start + batchSize).clamp(0, fileCandidates.length),
            );

            final batchPayloads = <(IndexEntry, Uint8List)?>[];
            for (final e in batch) {
              if (isCancelled?.call() ?? false) break;
              try {
                final raw = await BodyStore.readWithHandle(
                  raf,
                  e.fileOffset!,
                  e.fileLength!,
                );
                batchPayloads.add((e, raw));
              } catch (err) {
                if (kDebugMode) {
                  debugPrint(
                      '[Interceptly] SearchService file read error: $err');
                }
                batchPayloads.add(null);
              }
            }

            if (isCancelled?.call() ?? false) break;

            final futures = batchPayloads.map((payload) async {
              if (payload == null) return (false, null);
              final (e, raw) = payload;
              try {
                final checkReq =
                    !BodyDecodeService.isBinary(e.requestContentType);
                final checkRes =
                    !BodyDecodeService.isBinary(e.responseContentType);
                final job = (raw, checkReq, checkRes, q);
                final matched = raw.length > BodyDecodeService.computeThreshold
                    ? await compute(_matchPackedPayloadIsolate, job)
                    : _matchPackedPayloadIsolate(job);

                if (matched) {
                  return (true, e);
                }
              } catch (err) {
                if (kDebugMode) {
                  debugPrint('[Interceptly] SearchService decode error: $err');
                }
              }
              return (false, null);
            });

            final batchResults = await Future.wait(futures);
            if (isCancelled?.call() ?? false) break;

            var hasNewMatchInBatch = false;
            for (final (matched, e) in batchResults) {
              if (matched && e != null) {
                if (!matchedIds.contains(e.id)) {
                  matchedIds.add(e.id);
                  final item = SearchResult(
                    summary: e,
                    matchScopes: const {SearchMatchScope.body},
                  );
                  results.add(item);
                  resultIndexMap[e.id] = results.length - 1;
                  hasNewMatchInBatch = true;
                  if (limit != null && results.length >= limit) {
                    break;
                  }
                }
              }
            }

            if (hasNewMatchInBatch && onProgress != null) {
              onProgress(List.unmodifiable(results), isDone: false);
            }
          }
        } catch (err) {
          if (kDebugMode) {
            debugPrint('[Interceptly] SearchService file access error: $err');
          }
        } finally {
          await raf?.close();
        }
      }
    }

    if (isCancelled?.call() ?? false) return const [];
    onPhaseChange?.call(SearchPhase.done);
    onProgress?.call(List.unmodifiable(results), isDone: true);
    return results;
  }

  /// Matches a single entry against [queryLower] synchronously (for dynamic streaming updates in UI).
  static SearchResult? matchEntry(
    IndexEntry entry,
    String queryLower, {
    bool searchBody = true,
  }) {
    final trimmed = queryLower.trim();
    if (trimmed.isEmpty) return null;
    final q = trimmed.toLowerCase();

    final scopes = matchStructured(entry, q);

    if (searchBody && !_isBinaryOrEmpty(entry)) {
      if (entry.bodyLocation == BodyLocation.memory &&
          matchInlineBody(entry, q)) {
        scopes.add(SearchMatchScope.body);
      }
    }

    if (scopes.isEmpty) return null;
    return SearchResult(summary: entry, matchScopes: scopes);
  }

  /// Matches structured metadata: URL, HTTP Method, Headers, Error Message, Error Type.
  static Set<SearchMatchScope> matchStructured(
    RequestSummary entry,
    String queryLower,
  ) {
    final scopes = <SearchMatchScope>{};

    if (entry.url.toLowerCase().contains(queryLower) ||
        entry.method.toLowerCase().contains(queryLower)) {
      scopes.add(SearchMatchScope.url);
    }

    if ((entry.errorMessage?.toLowerCase().contains(queryLower) ?? false) ||
        (entry.errorType?.toLowerCase().contains(queryLower) ?? false)) {
      scopes.add(SearchMatchScope.error);
    }

    for (final h in entry.requestHeaders.entries) {
      if (h.key.toLowerCase().contains(queryLower) ||
          h.value.toLowerCase().contains(queryLower)) {
        scopes.add(SearchMatchScope.headers);
        break;
      }
    }

    if (!scopes.contains(SearchMatchScope.headers)) {
      for (final h in entry.responseHeaders.entries) {
        if (h.key.toLowerCase().contains(queryLower) ||
            h.value.toLowerCase().contains(queryLower)) {
          scopes.add(SearchMatchScope.headers);
          break;
        }
      }
    }

    return scopes;
  }

  /// Matches text inside inline in-memory bodies asynchronously, offloading
  /// payloads larger than [BodyDecodeService.computeThreshold] to a background isolate.
  static Future<bool> matchInlineBodyAsync(
    IndexEntry entry,
    String queryLower,
  ) async {
    final reqBytes = !BodyDecodeService.isBinary(entry.requestContentType)
        ? entry.inlineRequestBody
        : null;
    final resBytes = !BodyDecodeService.isBinary(entry.responseContentType)
        ? entry.inlineResponseBody
        : null;
    final totalBytes = (reqBytes?.length ?? 0) + (resBytes?.length ?? 0);
    if (totalBytes == 0) return false;

    final job = (
      reqBytes,
      entry.requestContentType,
      resBytes,
      entry.responseContentType,
      queryLower,
    );
    if (totalBytes > BodyDecodeService.computeThreshold) {
      return compute(_matchInlinePayloadsIsolate, job);
    }
    return _matchInlinePayloadsIsolate(job);
  }

  /// Matches text inside inline in-memory bodies (both request and response).
  static bool matchInlineBody(
    IndexEntry entry,
    String queryLower,
  ) {
    final reqBytes = !BodyDecodeService.isBinary(entry.requestContentType)
        ? entry.inlineRequestBody
        : null;
    final resBytes = !BodyDecodeService.isBinary(entry.responseContentType)
        ? entry.inlineResponseBody
        : null;
    if ((reqBytes?.length ?? 0) + (resBytes?.length ?? 0) == 0) return false;

    return _matchInlinePayloadsIsolate((
      reqBytes,
      entry.requestContentType,
      resBytes,
      entry.responseContentType,
      queryLower,
    ));
  }

  /// Matches text inside a file-backed body chunk using an open [RandomAccessFile] handle.
  static Future<bool> matchFileBody(
    RandomAccessFile raf,
    int offset,
    int length,
    String queryLower,
  ) async {
    try {
      final raw = await BodyStore.readWithHandle(raf, offset, length);
      final job = (raw, true, true, queryLower);
      return raw.length > BodyDecodeService.computeThreshold
          ? await compute(_matchPackedPayloadIsolate, job)
          : _matchPackedPayloadIsolate(job);
    } catch (_) {
      return false;
    }
  }

  static bool _matchInlinePayloadsIsolate(
    (Uint8List?, String?, Uint8List?, String?, String) job,
  ) {
    final (reqBytes, reqContentType, resBytes, resContentType, queryLower) =
        job;
    if (reqBytes != null && reqBytes.isNotEmpty) {
      final req = BodyDecodeService.decode(reqBytes, reqContentType);
      if (req != null &&
          !BodyDecodeService.isPlaceholder(req) &&
          _containsCaseInsensitive(req, queryLower)) {
        return true;
      }
    }

    if (resBytes != null && resBytes.isNotEmpty) {
      final res = BodyDecodeService.decode(resBytes, resContentType);
      if (res != null &&
          !BodyDecodeService.isPlaceholder(res) &&
          _containsCaseInsensitive(res, queryLower)) {
        return true;
      }
    }

    return false;
  }

  static bool _matchPackedPayloadIsolate(
    (Uint8List, bool, bool, String) job,
  ) {
    final (raw, checkReq, checkRes, queryLower) = job;
    final decoded = BodyDecodeService.unpackToText(raw);
    if (checkReq) {
      final reqText = decoded.$1;
      if (reqText != null &&
          !BodyDecodeService.isPlaceholder(reqText) &&
          _containsCaseInsensitive(reqText, queryLower)) {
        return true;
      }
    }
    if (checkRes) {
      final resText = decoded.$2;
      if (resText != null &&
          !BodyDecodeService.isPlaceholder(resText) &&
          _containsCaseInsensitive(resText, queryLower)) {
        return true;
      }
    }
    return false;
  }

  /// Case-insensitive substring check preserving full Unicode case-folding semantics.
  static bool _containsCaseInsensitive(String text, String queryLower) {
    if (queryLower.isEmpty) return true;
    return text.toLowerCase().contains(queryLower);
  }

  /// Guard to check if all payloads in [entry] are binary or empty.
  static bool _isBinaryOrEmpty(IndexEntry entry) {
    final reqBinaryOrEmpty = (entry.requestSizeBytes == 0 &&
            (entry.inlineRequestBody == null ||
                entry.inlineRequestBody!.isEmpty)) ||
        BodyDecodeService.isBinary(entry.requestContentType);

    final resBinaryOrEmpty = (entry.responseSizeBytes == 0 &&
            (entry.inlineResponseBody == null ||
                entry.inlineResponseBody!.isEmpty)) ||
        BodyDecodeService.isBinary(entry.responseContentType);

    return reqBinaryOrEmpty && resBinaryOrEmpty;
  }
}
