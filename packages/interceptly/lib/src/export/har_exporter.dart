import 'dart:convert';
import 'dart:typed_data';

import '../capture/body_bytes.dart';
import '../capture/capture_guard.dart';
import '../model/request_record.dart';
import '../session/body_decode_service.dart';

/// Exports captured request records to HAR 1.2 compatible maps.
class HarExporter {
  const HarExporter._();

  /// Default headers to redact on export if not explicitly specified.
  static const Set<String> _defaultRedactedHeaders = {
    'authorization',
    'cookie',
    'set-cookie',
    'x-api-key',
  };

  /// Default query parameters to redact on export if not explicitly specified.
  static const Set<String> _defaultRedactedQueryParams = {
    'token',
    'api_key',
    'password',
    'secret',
  };

  /// Converts [records] into a HAR-formatted JSON string.
  static String toJson(
    List<RequestRecord> records, {
    bool redactOnExport = false,
    Set<String>? redactedHeaders,
    Set<String>? redactedQueryParams,
  }) =>
      jsonEncode(toMap(
        records,
        redactOnExport: redactOnExport,
        redactedHeaders: redactedHeaders,
        redactedQueryParams: redactedQueryParams,
      ));

  /// Converts [records] into a HAR root object.
  static Map<String, Object?> toMap(
    List<RequestRecord> records, {
    bool redactOnExport = false,
    Set<String>? redactedHeaders,
    Set<String>? redactedQueryParams,
  }) {
    return {
      'log': {
        'version': '1.2',
        'creator': {'name': 'Interceptly', 'version': '0.0.1'},
        'pages': <Map<String, Object?>>[],
        'entries': records
            .map((r) => _entryFromRecord(
                  r,
                  redactOnExport: redactOnExport,
                  redactedHeaders: redactedHeaders,
                  redactedQueryParams: redactedQueryParams,
                ))
            .toList(),
      },
    };
  }

  /// Convenience alias for [toMap] — matches the [PostmanExporter] naming.
  static Map<String, Object?> fromRecords(
    List<RequestRecord> records, {
    bool redactOnExport = false,
    Set<String>? redactedHeaders,
    Set<String>? redactedQueryParams,
  }) =>
      toMap(
        records,
        redactOnExport: redactOnExport,
        redactedHeaders: redactedHeaders,
        redactedQueryParams: redactedQueryParams,
      );

  static Map<String, Object?> _entryFromRecord(
    RequestRecord r, {
    required bool redactOnExport,
    Set<String>? redactedHeaders,
    Set<String>? redactedQueryParams,
  }) {
    final effectiveReqHeaders = redactOnExport
        ? CaptureGuard.redactHeaders(
            r.requestHeaders,
            (redactedHeaders ?? _defaultRedactedHeaders)
                .map((h) => h.toLowerCase())
                .toSet(),
          )
        : (redactedHeaders != null && redactedHeaders.isNotEmpty
            ? CaptureGuard.redactHeaders(
                r.requestHeaders,
                redactedHeaders.map((h) => h.toLowerCase()).toSet(),
              )
            : r.requestHeaders);

    final effectiveResHeaders = redactOnExport
        ? CaptureGuard.redactHeaders(
            r.responseHeaders,
            (redactedHeaders ?? _defaultRedactedHeaders)
                .map((h) => h.toLowerCase())
                .toSet(),
          )
        : (redactedHeaders != null && redactedHeaders.isNotEmpty
            ? CaptureGuard.redactHeaders(
                r.responseHeaders,
                redactedHeaders.map((h) => h.toLowerCase()).toSet(),
              )
            : r.responseHeaders);

    final effectiveUrl = redactOnExport
        ? CaptureGuard.sanitizeUrl(
            r.url,
            (redactedQueryParams ?? _defaultRedactedQueryParams)
                .map((q) => q.toLowerCase())
                .toSet(),
          )
        : (redactedQueryParams != null && redactedQueryParams.isNotEmpty
            ? CaptureGuard.sanitizeUrl(
                r.url,
                redactedQueryParams.map((q) => q.toLowerCase()).toSet(),
              )
            : r.url);

    final uri = Uri.tryParse(effectiveUrl);
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
        'url': effectiveUrl,
        'httpVersion': 'HTTP/1.1',
        'cookies': <Object>[],
        'headers': _mapHeaders(effectiveReqHeaders),
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
        'headers': _mapHeaders(effectiveResHeaders),
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
