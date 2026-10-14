import 'dart:convert';
import 'dart:typed_data';

import '../capture/body_bytes.dart';
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
        'pages': <Map<String, Object?>>[],
        'entries': records.map(_entryFromRecord).toList(),
      },
    };
  }

  /// Convenience alias for [toMap] — matches the [PostmanExporter] naming.
  static Map<String, Object?> fromRecords(List<RequestRecord> records) =>
      toMap(records);

  static Map<String, Object?> _entryFromRecord(RequestRecord r) {
    final uri = Uri.tryParse(r.url);
    final queryString = uri != null && uri.hasQuery
        ? uri.queryParametersAll.entries
            .expand((e) => e.value.map((v) => {'name': e.key, 'value': v}))
            .toList()
        : <Map<String, String>>[];

    final safeStatus = r.statusCode > 0 ? r.statusCode : 0;
    final safeStatusText = r.statusCode > 0
        ? ''
        : (r.errorMessage ?? (r.statusCode == 0 ? 'Pending' : 'Aborted'));

    return {
      'startedDateTime': r.timestamp.toUtc().toIso8601String(),
      'time': r.durationMs,
      'timings': {
        'blocked': -1,
        'dns': -1,
        'connect': -1,
        'send': 0,
        'wait': r.durationMs,
        'receive': 0,
        'ssl': -1,
      },
      'cache': <String, Object?>{},
      'request': {
        'method': r.method.replaceAll(RegExp(r'[\r\n]'), '').trim(),
        'url': r.url,
        'httpVersion': 'HTTP/1.1',
        'cookies': <Object>[],
        'headers': _mapHeaders(r.requestHeaders),
        'queryString': queryString,
        'headersSize': -1,
        'bodySize': r.requestSizeBytes,
        'postData': _buildPostData(r),
      },
      'response': {
        'status': safeStatus,
        'statusText': safeStatusText,
        'httpVersion': 'HTTP/1.1',
        'cookies': <Object>[],
        'headers': _mapHeaders(r.responseHeaders),
        'content': {
          'size': r.responseSizeBytes,
          'mimeType': r.responseContentType ?? 'application/octet-stream',
          'text': _safeBody(r.responseBodyBytes, r.responseBodyPreview),
        },
        'redirectURL': '',
        'headersSize': -1,
        'bodySize': r.responseSizeBytes,
      },
    };
  }

  static List<Map<String, String>> _mapHeaders(Map<String, String> headers) {
    return mapHeaderEntries(headers, keyName: 'name', valueName: 'value');
  }

  static Map<String, Object?>? _buildPostData(RequestRecord r) {
    final body = _safeBody(r.requestBodyBytes, r.requestBodyPreview);
    if (body.isEmpty) {
      return null;
    }
    return {
      'mimeType': r.requestContentType ?? 'application/octet-stream',
      'text': body,
    };
  }

  /// Returns decoded body text, falling back to preview or empty for binary placeholders.
  static String _safeBody(Uint8List? bytes, String? preview) {
    if (bytes != null && bytes.isNotEmpty) {
      try {
        final decoded = utf8.decode(bytes);
        if (!BodyDecodeService.isPlaceholder(decoded)) return decoded;
      } catch (_) {}
    }
    if (preview == null || BodyDecodeService.isPlaceholder(preview)) return '';
    return preview;
  }
}
