
import 'package:flutter/foundation.dart';
import 'package:interceptly/src/ui/widgets/json_viewer.dart';

import '../../model/request_record.dart';
import '../../session/body_decode_service.dart';

class DetailMatch {
  const DetailMatch({required this.tabIndex, required this.section});
  final int tabIndex;
  final DetailSection section;
}

enum DetailSection {
  overviewUrl,
  overviewMethod,
  overviewStatus,
  overviewDuration,
  overviewTime,
  overviewNote,
  queryParams,
  requestHeaders,
  requestBody,
  responseHeaders,
  responseBody,
  errorType,
  errorMessage,
}

/// Synchronous variant — kept for backward compatibility with code paths that
/// already run inside an isolate (it doesn't snapshot the record twice).
List<DetailMatch> computeMatches(
  RequestRecord record,
  String query,
  bool isWs,
  dynamic Function(String?) tryParseJson,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];

  final matches = <DetailMatch>[];

  int countOccurrences(String? text) {
    if (text == null || text.isEmpty) return 0;
    int c = 0;
    int start = 0;
    final lower = text.toLowerCase();
    while (true) {
      final idx = lower.indexOf(q, start);
      if (idx < 0) break;
      c++;
      start = idx + q.length;
    }
    return c;
  }

  void addMatches(int count, int tabIndex, DetailSection section) {
    for (int i = 0; i < count; i++) {
      matches.add(DetailMatch(tabIndex: tabIndex, section: section));
    }
  }

  // Overview
  addMatches(countOccurrences(record.url), 0, DetailSection.overviewUrl);
  addMatches(countOccurrences(record.method), 0, DetailSection.overviewMethod);
  addMatches(
    countOccurrences(
      record.statusCode > 0 ? record.statusCode.toString() : 'N/A',
    ),
    0,
    DetailSection.overviewStatus,
  );
  addMatches(
    countOccurrences('${record.durationMs} ms'),
    0,
    DetailSection.overviewDuration,
  );
  addMatches(
    countOccurrences(record.timestamp.toIso8601String()),
    0,
    DetailSection.overviewTime,
  );
  if (record.isBodyTruncated) {
    addMatches(
      countOccurrences('Body truncated — response exceeded the size limit.'),
      0,
      DetailSection.overviewNote,
    );
  }

  if (!isWs) {
    final uri = Uri.tryParse(record.url);
    if (uri != null && uri.queryParameters.isNotEmpty) {
      addMatches(
        JsonViewer.countMatches(uri.queryParameters, query),
        1,
        DetailSection.queryParams,
      );
    }
    addMatches(
      JsonViewer.countMatches(record.requestHeaders, query),
      1,
      DetailSection.requestHeaders,
    );
    addMatches(
      JsonViewer.countMatches(tryParseJson(record.requestBodyPreview), query),
      1,
      DetailSection.requestBody,
    );

    addMatches(
      JsonViewer.countMatches(record.responseHeaders, query),
      2,
      DetailSection.responseHeaders,
    );
    addMatches(
      JsonViewer.countMatches(tryParseJson(record.responseBodyPreview), query),
      2,
      DetailSection.responseBody,
    );

    addMatches(
      JsonViewer.countMatches(record.errorType ?? 'None', query),
      3,
      DetailSection.errorType,
    );
    addMatches(
      JsonViewer.countMatches(record.errorMessage ?? 'None', query),
      3,
      DetailSection.errorMessage,
    );
  }

  return matches;
}

/// Snapshot model passed into [compute] — `RequestRecord` contains `Map`s of
/// only primitive types so a JSON snapshot is safe and cheap.
RequestRecordSnapshot snapshotRecord(RequestRecord r) => RequestRecordSnapshot(
      id: r.id,
      method: r.method,
      url: r.url,
      statusCode: r.statusCode,
      durationMs: r.durationMs,
      requestSizeBytes: r.requestSizeBytes,
      responseSizeBytes: r.responseSizeBytes,
      timestampIso: r.timestamp.toIso8601String(),
      isBodyTruncated: r.isBodyTruncated,
      requestHeaders: r.requestHeaders,
      responseHeaders: r.responseHeaders,
      requestContentType: r.requestContentType,
      responseContentType: r.responseContentType,
      requestBodyPreview: r.requestBodyPreview,
      responseBodyPreview: r.responseBodyPreview,
      errorType: r.errorType,
      errorMessage: r.errorMessage,
    );

/// Async variant of [computeMatches] that runs the heavy walk on a background
/// isolate. The `tryParseJson` callback is approximated inside the isolate
/// by a local helper that does `jsonDecode` directly.
Future<List<DetailMatch>> computeMatchesAsync(
  RequestRecord record,
  String query,
  bool isWs,
) {
  if (query.trim().isEmpty) {
    return SynchronousFuture(const <DetailMatch>[]);
  }
  try {
    final snapshot = snapshotRecord(record);
    return compute(
      _computeMatchesIsolate,
      _IsolateArgs(snapshot, query, isWs),
    );
  } catch (_) {
    return SynchronousFuture(
        computeMatches(record, query, isWs, _syncParseJson));
  }
}

dynamic jsonDecodeSafe(String text) {
  return BodyDecodeService.decodeJsonLenient(text);
}

dynamic _syncParseJson(String? s) => s == null ? null : jsonDecodeSafe(s);

class _IsolateArgs {
  final RequestRecordSnapshot record;
  final String query;
  final bool isWs;
  const _IsolateArgs(
    this.record,
    this.query,
    this.isWs,
  );
}

List<DetailMatch> _computeMatchesIsolate(_IsolateArgs args) {
  final q = args.query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final matches = <DetailMatch>[];

  int countOccurrences(String? text) {
    if (text == null || text.isEmpty) return 0;
    int c = 0;
    int start = 0;
    final lower = text.toLowerCase();
    while (true) {
      final idx = lower.indexOf(q, start);
      if (idx < 0) break;
      c++;
      start = idx + q.length;
    }
    return c;
  }

  void addMatches(int count, int tabIndex, DetailSection section) {
    for (int i = 0; i < count; i++) {
      matches.add(DetailMatch(tabIndex: tabIndex, section: section));
    }
  }

  final r = args.record;
  addMatches(countOccurrences(r.url), 0, DetailSection.overviewUrl);
  addMatches(countOccurrences(r.method), 0, DetailSection.overviewMethod);
  addMatches(
    countOccurrences(r.statusCode > 0 ? r.statusCode.toString() : 'N/A'),
    0,
    DetailSection.overviewStatus,
  );
  addMatches(
    countOccurrences('${r.durationMs} ms'),
    0,
    DetailSection.overviewDuration,
  );
  addMatches(countOccurrences(r.timestampIso), 0, DetailSection.overviewTime);
  if (r.isBodyTruncated) {
    addMatches(
      countOccurrences('Body truncated — response exceeded the size limit.'),
      0,
      DetailSection.overviewNote,
    );
  }

  if (!args.isWs) {
    final uri = Uri.tryParse(r.url);
    if (uri != null && uri.queryParameters.isNotEmpty) {
      addMatches(
        JsonViewer.countMatches(uri.queryParameters, args.query),
        1,
        DetailSection.queryParams,
      );
    }
    addMatches(
      JsonViewer.countMatches(r.requestHeaders, args.query),
      1,
      DetailSection.requestHeaders,
    );
    final reqBodyParsed = r.requestBodyPreview == null
        ? null
        : jsonDecodeSafe(r.requestBodyPreview!);
    final resBodyParsed = r.responseBodyPreview == null
        ? null
        : jsonDecodeSafe(r.responseBodyPreview!);
    addMatches(
      JsonViewer.countMatches(reqBodyParsed, args.query),
      1,
      DetailSection.requestBody,
    );
    addMatches(
      JsonViewer.countMatches(r.responseHeaders, args.query),
      2,
      DetailSection.responseHeaders,
    );
    addMatches(
      JsonViewer.countMatches(resBodyParsed, args.query),
      2,
      DetailSection.responseBody,
    );
    addMatches(
      JsonViewer.countMatches(r.errorType ?? 'None', args.query),
      3,
      DetailSection.errorType,
    );
    addMatches(
      JsonViewer.countMatches(r.errorMessage ?? 'None', args.query),
      3,
      DetailSection.errorMessage,
    );
  }

  return matches;
}

class RequestRecordSnapshot {
  final String id;
  final String method;
  final String url;
  final int statusCode;
  final int durationMs;
  final int requestSizeBytes;
  final int responseSizeBytes;
  final String timestampIso;
  final bool isBodyTruncated;
  final Map<String, String> requestHeaders;
  final Map<String, String> responseHeaders;
  final String? requestContentType;
  final String? responseContentType;
  final String? requestBodyPreview;
  final String? responseBodyPreview;
  final String? errorType;
  final String? errorMessage;

  const RequestRecordSnapshot({
    required this.id,
    required this.method,
    required this.url,
    required this.statusCode,
    required this.durationMs,
    required this.requestSizeBytes,
    required this.responseSizeBytes,
    required this.timestampIso,
    required this.isBodyTruncated,
    required this.requestHeaders,
    required this.responseHeaders,
    required this.requestContentType,
    required this.responseContentType,
    required this.requestBodyPreview,
    required this.responseBodyPreview,
    required this.errorType,
    required this.errorMessage,
  });
}
