import 'package:flutter/foundation.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';

import '../../model/body_truncation.dart';
import '../../model/request_record.dart';
import '../../engine/body_decode_service.dart';
import '../format.dart';
import '../widgets/error_summary.dart';

export '../format.dart' show formatBytes;

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

/// Tab index constants for detail sections.
const int overviewTabIndex = 0;
const int requestTabIndex = 1;
const int responseTabIndex = 2;
const int errorTabIndex = 3;

/// Counts how many times [lowerQuery] appears in [text] (case-insensitively).
int countOccurrences(String? text, String lowerQuery) {
  if (text == null || text.isEmpty || lowerQuery.isEmpty) return 0;
  var count = 0;
  var start = 0;
  final lower = text.toLowerCase();
  while (true) {
    final idx = lower.indexOf(lowerQuery, start);
    if (idx < 0) break;
    count++;
    start = idx + lowerQuery.length;
  }
  return count;
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

Object? formatBodyData({
  required String? contentType,
  required String? bodyPreview,
  Object? Function(String?)? tryParseJson,
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

List<DetailMatch> _computeMatchesInternal({
  required String url,
  required String method,
  required int statusCode,
  required int durationMs,
  required int requestSizeBytes,
  required int responseSizeBytes,
  required bool hasError,
  required String? errorType,
  required String? errorMessage,
  required String timestampString,
  required BodyTruncation requestTruncation,
  required BodyTruncation responseTruncation,
  required Map<String, String> requestHeaders,
  required Map<String, String> responseHeaders,
  required String? requestContentType,
  required String? responseContentType,
  required String? requestBodyPreview,
  required String? responseBodyPreview,
  required String query,
  required bool isWs,
  required Object? Function(String?) tryParseJson,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];

  final matches = <DetailMatch>[];

  void addMatches(int count, int tabIndex, DetailSection section) {
    for (var i = 0; i < count; i++) {
      matches.add(DetailMatch(tabIndex: tabIndex, section: section));
    }
  }

  addMatches(
      countOccurrences(url, q), overviewTabIndex, DetailSection.overviewUrl);
  addMatches(countOccurrences(method, q), overviewTabIndex,
      DetailSection.overviewMethod);
  addMatches(
    countOccurrences(statusCode > 0 ? statusCode.toString() : 'N/A', q),
    overviewTabIndex,
    DetailSection.overviewStatus,
  );
  addMatches(
    countOccurrences('$durationMs ms', q),
    overviewTabIndex,
    DetailSection.overviewDuration,
  );
  addMatches(
    countOccurrences(formatBytes(requestSizeBytes), q),
    overviewTabIndex,
    DetailSection.overviewRequestSize,
  );
  addMatches(
    countOccurrences(
        statusCode == 0 && !hasError
            ? 'loading…'
            : formatBytes(responseSizeBytes),
        q),
    overviewTabIndex,
    DetailSection.overviewResponseSize,
  );
  if (hasError) {
    final shortErr = summarizeRequestError(
      errorType: errorType,
      errorMessage: errorMessage,
    );
    addMatches(countOccurrences(shortErr, q), overviewTabIndex,
        DetailSection.overviewError);
  }
  addMatches(
    countOccurrences(timestampString, q),
    overviewTabIndex,
    DetailSection.overviewTime,
  );
  for (final notice in [
    ...bodyTruncationNotices(requestTruncation),
    ...bodyTruncationNotices(responseTruncation),
  ]) {
    addMatches(countOccurrences(notice, q), overviewTabIndex,
        DetailSection.requestBody);
  }

  if (!isWs) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.queryParameters.isNotEmpty) {
      addMatches(
        JsonViewer.countMatches(uri.queryParameters, query),
        requestTabIndex,
        DetailSection.queryParams,
      );
    }
    addMatches(
      JsonViewer.countMatches(requestHeaders, query),
      requestTabIndex,
      DetailSection.requestHeaders,
    );
    final reqBody = formatBodyData(
      contentType: requestContentType,
      bodyPreview: requestBodyPreview,
      tryParseJson: tryParseJson,
    );
    addMatches(
      JsonViewer.countMatches(reqBody, query),
      requestTabIndex,
      DetailSection.requestBody,
    );

    addMatches(
      JsonViewer.countMatches(responseHeaders, query),
      responseTabIndex,
      DetailSection.responseHeaders,
    );
    final resBody = formatBodyData(
      contentType: responseContentType,
      bodyPreview: responseBodyPreview,
      tryParseJson: tryParseJson,
    );
    addMatches(
      JsonViewer.countMatches(resBody, query),
      responseTabIndex,
      DetailSection.responseBody,
    );

    if (hasError) {
      final shortErr = summarizeRequestError(
        errorType: errorType,
        errorMessage: errorMessage,
      );
      addMatches(
        JsonViewer.countMatches(shortErr, query),
        errorTabIndex,
        DetailSection.errorSummary,
      );
    }
    addMatches(
      JsonViewer.countMatches(errorType ?? 'None', query),
      errorTabIndex,
      DetailSection.errorType,
    );
    addMatches(
      JsonViewer.countMatches(errorMessage ?? 'None', query),
      errorTabIndex,
      DetailSection.errorMessage,
    );
  }

  return matches;
}

/// Synchronous variant — kept for backward compatibility with code paths that
/// already run inside an isolate (it doesn't snapshot the record twice).
List<DetailMatch> computeMatches(
  RequestRecord record,
  String query,
  bool isWs,
  Object? Function(String?) tryParseJson,
) {
  return _computeMatchesInternal(
    url: record.url,
    method: record.method,
    statusCode: record.statusCode,
    durationMs: record.durationMs,
    requestSizeBytes: record.requestSizeBytes,
    responseSizeBytes: record.responseSizeBytes,
    hasError: record.hasError,
    errorType: record.errorType,
    errorMessage: record.errorMessage,
    timestampString: record.timestamp.toIso8601String(),
    requestTruncation: record.requestTruncation,
    responseTruncation: record.responseTruncation,
    requestHeaders: record.requestHeaders,
    responseHeaders: record.responseHeaders,
    requestContentType: record.requestContentType,
    responseContentType: record.responseContentType,
    requestBodyPreview: record.requestBodyPreview,
    responseBodyPreview: record.responseBodyPreview,
    query: query,
    isWs: isWs,
    tryParseJson: tryParseJson,
  );
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
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
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

Object? jsonDecodeSafe(String text) {
  return BodyDecodeService.decodeJsonLenient(text);
}

Object? _syncParseJson(String? s) => s == null ? null : jsonDecodeSafe(s);

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
  final r = args.record;
  return _computeMatchesInternal(
    url: r.url,
    method: r.method,
    statusCode: r.statusCode,
    durationMs: r.durationMs,
    requestSizeBytes: r.requestSizeBytes,
    responseSizeBytes: r.responseSizeBytes,
    hasError: r.hasError,
    errorType: r.errorType,
    errorMessage: r.errorMessage,
    timestampString: r.timestampIso,
    requestTruncation: r.requestTruncation,
    responseTruncation: r.responseTruncation,
    requestHeaders: r.requestHeaders,
    responseHeaders: r.responseHeaders,
    requestContentType: r.requestContentType,
    responseContentType: r.responseContentType,
    requestBodyPreview: r.requestBodyPreview,
    responseBodyPreview: r.responseBodyPreview,
    query: args.query,
    isWs: args.isWs,
    tryParseJson: (s) => s != null ? jsonDecodeSafe(s) : null,
  );
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

  bool get hasError =>
      errorType != null || errorMessage != null || statusCode >= 400;

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
