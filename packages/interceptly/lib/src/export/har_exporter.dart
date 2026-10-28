import 'dart:convert';
import 'dart:typed_data';

import '../engine/body_decode_service.dart';
import '../model/request_record.dart';

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
        'creator': {'name': 'Interceptly', 'version': '2.0.0'},
        'pages': <Map<String, Object?>>[],
        'entries': records.map(_entryFromRecord).toList(),
      },
    };
  }

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
        'content': _buildResponseContent(r),
        'redirectURL': '',
        'headersSize': -1,
        'bodySize': r.responseSizeBytes,
      },
    };
  }

  static Map<String, Object?> _buildResponseContent(RequestRecord r) {
    final bytes = r.responseBodyBytes;
    final mimeType = r.responseContentType ?? 'application/octet-stream';
    final content = <String, Object?>{
      'size': r.responseSizeBytes,
      'mimeType': mimeType,
    };
    if (r.responseTruncation.hasDataLoss) {
      content['comment'] =
          'Payload truncated from original ${r.responseSizeBytes} bytes';
    }

    if (bytes != null && bytes.isNotEmpty) {
      if (BodyDecodeService.isBinary(r.responseContentType)) {
        content['text'] = base64Encode(bytes);
        content['encoding'] = 'base64';
        return content;
      }
      try {
        final decoded = utf8.decode(bytes);
        if (!BodyDecodeService.isPlaceholder(decoded)) {
          content['text'] = decoded;
          return content;
        }
      } catch (_) {}
      content['text'] = base64Encode(bytes);
      content['encoding'] = 'base64';
      return content;
    }

    content['text'] = _safeBody(bytes, r.responseBodyPreview);
    return content;
  }

  static List<Map<String, String>> _mapHeaders(Map<String, String> headers) {
    return headers.entries
        .map((entry) => {'name': entry.key, 'value': entry.value})
        .toList();
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
