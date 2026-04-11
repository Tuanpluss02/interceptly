import 'dart:convert';

import '../model/request_record.dart';
import '../session/body_decode_service.dart';

/// Exports captured request records to HAR 1.2 compatible maps.
class HarExporter {
  const HarExporter._();

  /// Converts [records] into a HAR-formatted JSON string.
  static String toJson(List<RequestRecord> records) =>
      jsonEncode(toMap(records));

  /// Converts [records] into a HAR root object.
  static Map<String, Object?> toMap(List<RequestRecord> records) {
    return {
      'log': {
        'version': '1.2',
        'creator': {'name': 'Interceptly', 'version': '0.0.1'},
        'entries': records.map(_entryFromRecord).toList(),
      },
    };
  }

  static Map<String, Object?> _entryFromRecord(RequestRecord r) {
    return {
      'startedDateTime': r.timestamp.toIso8601String(),
      'time': r.durationMs,
      'timings': {'send': 0, 'wait': r.durationMs, 'receive': 0},
      'request': {
        'method': r.method,
        'url': r.url,
        'httpVersion': 'HTTP/1.1',
        'cookies': [],
        'headers': _mapHeaders(r.requestHeaders),
        'queryString': [],
        'headersSize': -1,
        'bodySize': r.requestSizeBytes,
        'postData': _buildPostData(r),
      },
      'response': {
        'status': r.statusCode,
        'statusText': '',
        'httpVersion': 'HTTP/1.1',
        'cookies': [],
        'headers': _mapHeaders(r.responseHeaders),
        'content': {
          'size': r.responseSizeBytes,
          'mimeType': r.responseContentType ?? 'application/octet-stream',
          'text': _safeBody(r.responseBodyPreview),
        },
        'redirectURL': '',
        'headersSize': -1,
        'bodySize': r.responseSizeBytes,
      },
    };
  }

  static List<Map<String, String>> _mapHeaders(Map<String, String> headers) {
    return headers.entries
        .map((e) => {'name': e.key, 'value': e.value})
        .toList();
  }

  static Map<String, Object?>? _buildPostData(RequestRecord r) {
    final body = r.requestBodyPreview;
    if (body == null || body.isEmpty || BodyDecodeService.isPlaceholder(body)) {
      return null;
    }
    return {
      'mimeType': r.requestContentType ?? 'application/octet-stream',
      'text': body,
    };
  }

  /// Returns empty text for binary placeholders in HAR content.
  static String _safeBody(String? body) {
    if (body == null || BodyDecodeService.isPlaceholder(body)) return '';
    return body;
  }
}
