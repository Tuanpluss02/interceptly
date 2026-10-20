import 'dart:io';

import '../model/index_entry.dart';
import '../model/request_summary.dart';
import '../model/search_match_scope.dart';
import 'body_decode_service.dart';
import 'body_store.dart';

/// Pure static search matcher used by both UI progressive search and headless engine/service extensions.
abstract final class SearchMatcher {
  /// Matches structured metadata: URL, HTTP Method, Headers, Error Message, Error Type.
  ///
  /// Returns a set of [SearchMatchScope] that matched [queryLower] (which must be lowercase).
  static Set<SearchMatchScope> matchStructured(
    RequestSummary entry,
    String queryLower,
  ) {
    final scopes = <SearchMatchScope>{};

    // 1. URL and method
    if (entry.url.toLowerCase().contains(queryLower) ||
        entry.method.toLowerCase().contains(queryLower)) {
      scopes.add(SearchMatchScope.url);
    }

    // 2. Error message and error type
    if ((entry.errorMessage?.toLowerCase().contains(queryLower) ?? false) ||
        (entry.errorType?.toLowerCase().contains(queryLower) ?? false)) {
      scopes.add(SearchMatchScope.error);
    }

    // 3. Request headers (keys and values)
    for (final h in entry.requestHeaders.entries) {
      if (h.key.toLowerCase().contains(queryLower) ||
          h.value.toLowerCase().contains(queryLower)) {
        scopes.add(SearchMatchScope.headers);
        break;
      }
    }

    // 4. Response headers (keys and values)
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

  /// Matches text inside inline in-memory bodies (both request and response).
  static bool matchInlineBody(
    IndexEntry entry,
    String queryLower,
  ) {
    final req = BodyDecodeService.decode(
      entry.inlineRequestBody,
      entry.requestContentType,
    )?.toLowerCase();
    if (req != null && req.contains(queryLower)) return true;

    final res = BodyDecodeService.decode(
      entry.inlineResponseBody,
      entry.responseContentType,
    )?.toLowerCase();
    return res != null && res.contains(queryLower);
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
      final decoded = BodyDecodeService.unpackToText(raw);
      final combined = '${decoded.$1 ?? ''}\n${decoded.$2 ?? ''}'.toLowerCase();
      return combined.contains(queryLower);
    } catch (_) {
      return false;
    }
  }
}
