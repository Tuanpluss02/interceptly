import 'package:interceptly/src/ui/widgets/json_viewer.dart';

import '../../model/request_record.dart';

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
        record.statusCode > 0 ? record.statusCode.toString() : 'N/A'),
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
    // Request tab index 1
    final uri = Uri.tryParse(record.url);
    if (uri != null && uri.queryParameters.isNotEmpty) {
      addMatches(JsonViewer.countMatches(uri.queryParameters, query), 1,
          DetailSection.queryParams);
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

    // Response tab index 2
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

    // Error tab index 3
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
