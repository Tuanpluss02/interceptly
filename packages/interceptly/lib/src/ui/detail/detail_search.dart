import 'package:flutter/foundation.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';

import '../../model/body_truncation.dart';
import '../../model/request_record.dart';
import '../../session/body_decode_service.dart';
import '../widgets/error_summary.dart';

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
  overviewRequestSize,
  overviewResponseSize,
  overviewError,
  overviewTime,
  overviewNote,
  queryParams,
  requestHeaders,
  requestBody,
  responseHeaders,
  responseBody,
  errorSummary,
  errorType,
  errorMessage,
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

Map<String, dynamic> parseFormUrlEncoded(String body) {
  try {
    return Uri.splitQueryString(body);
  } catch (_) {
    final map = <String, String>{};
    for (final part in body.split('&')) {
      if (part.isEmpty) continue;
      final idx = part.indexOf('=');
      if (idx < 0) {
        map[Uri.decodeQueryComponent(part)] = '';
      } else {
        final k = part.substring(0, idx);
        final v = part.substring(idx + 1);
        map[Uri.decodeQueryComponent(k)] = Uri.decodeQueryComponent(v);
      }
    }
    return map;
  }
}

Map<String, dynamic> parseMultipartSummary(String body) {
  final fields = <String, String>{};
  final files = <Map<String, String>>[];
  final rawLines = <String>[];

  for (final line in body.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    if (trimmed.startsWith('[field] ')) {
      final payload = trimmed.substring(8);
      final idx = payload.indexOf('=');
      if (idx > 0) {
        fields[payload.substring(0, idx).trim()] =
            payload.substring(idx + 1).trim();
      } else {
        rawLines.add(trimmed);
      }
      continue;
    }

    if (trimmed.startsWith('[file] ')) {
      final payload = trimmed.substring(7);
      final idx = payload.indexOf(':');
      if (idx > 0) {
        final field = payload.substring(0, idx).trim();
        final rest = payload.substring(idx + 1).trim();
        files.add({'field': field, 'value': rest});
      } else {
        files.add({'value': payload});
      }
      continue;
    }

    rawLines.add(trimmed);
  }

  return {
    'fields': fields,
    'files': files,
    if (rawLines.isNotEmpty) 'raw': rawLines,
  };
}

dynamic formatBodyData({
  required String? contentType,
  required String? bodyPreview,
  dynamic Function(String?)? tryParseJson,
}) {
  if (bodyPreview == null || bodyPreview.isEmpty) return 'No Data';
  final ct = (contentType ?? '').toLowerCase();

  if (ct.contains('application/x-www-form-urlencoded')) {
    return parseFormUrlEncoded(bodyPreview);
  }

  if (ct.contains('multipart/form-data')) {
    return parseMultipartSummary(bodyPreview);
  }

  if (ct.contains('application/graphql')) {
    return {'query': bodyPreview};
  }

  final parsed = tryParseJson != null
      ? tryParseJson(bodyPreview)
      : jsonDecodeSafe(bodyPreview);
  if (parsed is Map<String, dynamic> &&
      (parsed.containsKey('query') ||
          parsed.containsKey('operationName') ||
          parsed.containsKey('variables'))) {
    return {
      'operationName': parsed['operationName'],
      'query': parsed['query'],
      'variables': parsed['variables'],
    };
  }

  return parsed;
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
    countOccurrences(formatBytes(record.requestSizeBytes)),
    0,
    DetailSection.overviewRequestSize,
  );
  addMatches(
    countOccurrences(record.statusCode == 0 && !record.hasError
        ? 'loading…'
        : formatBytes(record.responseSizeBytes)),
    0,
    DetailSection.overviewResponseSize,
  );
  if (record.hasError) {
    final shortErr = summarizeRequestError(
      errorType: record.errorType,
      errorMessage: record.errorMessage,
    );
    addMatches(countOccurrences(shortErr), 0, DetailSection.overviewError);
  }
  addMatches(
    countOccurrences(record.timestamp.toIso8601String()),
    0,
    DetailSection.overviewTime,
  );
  for (final notice in [
    ...bodyTruncationNotices(record.requestTruncation),
    ...bodyTruncationNotices(record.responseTruncation),
  ]) {
    addMatches(countOccurrences(notice), 0, DetailSection.requestBody);
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
    final reqBody = formatBodyData(
      contentType: record.requestContentType,
      bodyPreview: record.requestBodyPreview,
      tryParseJson: tryParseJson,
    );
    addMatches(
      JsonViewer.countMatches(reqBody, query),
      1,
      DetailSection.requestBody,
    );

    addMatches(
      JsonViewer.countMatches(record.responseHeaders, query),
      2,
      DetailSection.responseHeaders,
    );
    final resBody = formatBodyData(
      contentType: record.responseContentType,
      bodyPreview: record.responseBodyPreview,
      tryParseJson: tryParseJson,
    );
    addMatches(
      JsonViewer.countMatches(resBody, query),
      2,
      DetailSection.responseBody,
    );

    if (record.hasError) {
      final shortErr = summarizeRequestError(
        errorType: record.errorType,
        errorMessage: record.errorMessage,
      );
      addMatches(
        JsonViewer.countMatches(shortErr, query),
        3,
        DetailSection.errorSummary,
      );
    }
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

/// Single source of truth for the truncation notice wording.
///
/// Both the on-screen banner and the in-detail search matcher read this, so a
/// query can never match text the user cannot actually see.
List<String> bodyTruncationNotices(BodyTruncation truncation) {
  if (!truncation.isTruncated) return const [];
  final retained = formatTruncationBytes(truncation.retainedBytes);
  final original = formatTruncationBytes(truncation.originalBytes);
  return switch (truncation.stage) {
    TruncationStage.none => const [],
    TruncationStage.preview => [
        'Showing the first $retained of $original here. Nothing is lost — '
            'exports and replay still carry the full body.'
      ],
    TruncationStage.storage => [
        'Stored only the first $retained of $original (maxBodyBytes). The rest '
            'was discarded before it could be saved.'
      ],
    TruncationStage.storageAndPreview => [
        'Body exceeded maxBodyBytes, so only $retained of $original survived — '
            'and this view shows less than that. The discarded part is '
            'unrecoverable.'
      ],
  };
}

String formatTruncationBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
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
      requestTruncation: r.requestTruncation,
      responseTruncation: r.responseTruncation,
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
  addMatches(
    countOccurrences(formatBytes(r.requestSizeBytes)),
    0,
    DetailSection.overviewRequestSize,
  );
  addMatches(
    countOccurrences(r.statusCode == 0 && r.errorType == null
        ? 'loading…'
        : formatBytes(r.responseSizeBytes)),
    0,
    DetailSection.overviewResponseSize,
  );
  if (r.errorType != null || r.errorMessage != null) {
    final shortErr = summarizeRequestError(
      errorType: r.errorType,
      errorMessage: r.errorMessage,
    );
    addMatches(countOccurrences(shortErr), 0, DetailSection.overviewError);
  }
  addMatches(countOccurrences(r.timestampIso), 0, DetailSection.overviewTime);
  for (final notice in [
    ...bodyTruncationNotices(r.requestTruncation),
    ...bodyTruncationNotices(r.responseTruncation),
  ]) {
    addMatches(countOccurrences(notice), 0, DetailSection.requestBody);
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
    final reqBody = formatBodyData(
      contentType: r.requestContentType,
      bodyPreview: r.requestBodyPreview,
      tryParseJson: (s) => s != null ? jsonDecodeSafe(s) : null,
    );
    addMatches(
      JsonViewer.countMatches(reqBody, args.query),
      1,
      DetailSection.requestBody,
    );
    addMatches(
      JsonViewer.countMatches(r.responseHeaders, args.query),
      2,
      DetailSection.responseHeaders,
    );
    final resBody = formatBodyData(
      contentType: r.responseContentType,
      bodyPreview: r.responseBodyPreview,
      tryParseJson: (s) => s != null ? jsonDecodeSafe(s) : null,
    );
    addMatches(
      JsonViewer.countMatches(resBody, args.query),
      2,
      DetailSection.responseBody,
    );
    if (r.errorType != null || r.errorMessage != null) {
      final shortErr = summarizeRequestError(
        errorType: r.errorType,
        errorMessage: r.errorMessage,
      );
      addMatches(
        JsonViewer.countMatches(shortErr, args.query),
        3,
        DetailSection.errorSummary,
      );
    }
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
  final BodyTruncation requestTruncation;
  final BodyTruncation responseTruncation;
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
    required this.requestTruncation,
    required this.responseTruncation,
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
