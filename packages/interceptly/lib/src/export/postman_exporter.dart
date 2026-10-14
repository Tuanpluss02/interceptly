import 'dart:convert';

import '../capture/body_bytes.dart';
import '../capture/capture_guard.dart';
import '../model/request_record.dart';
import '../session/body_decode_service.dart';

/// Exports captured request records to Postman Collection v2.1 format.
///
/// The generated JSON can be imported directly into Postman via
/// File → Import → Raw text / file.
class PostmanExporter {
  const PostmanExporter._();

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

  /// Converts [records] into a Postman Collection v2.1 JSON string.
  static String toJson(
    List<RequestRecord> records, {
    String collectionName = 'Interceptly Export',
    bool redactOnExport = false,
    Set<String>? redactedHeaders,
    Set<String>? redactedQueryParams,
  }) =>
      jsonEncode(toMap(
        records,
        collectionName: collectionName,
        redactOnExport: redactOnExport,
        redactedHeaders: redactedHeaders,
        redactedQueryParams: redactedQueryParams,
      ));

  /// Converts [records] into a Postman Collection v2.1 root object.
  static Map<String, Object?> toMap(
    List<RequestRecord> records, {
    String collectionName = 'Interceptly Export',
    bool redactOnExport = false,
    Set<String>? redactedHeaders,
    Set<String>? redactedQueryParams,
  }) {
    return {
      'info': {
        'name': collectionName,
        'schema':
            'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
      },
      'item': records
          .map((r) => _itemFromRecord(
                r,
                redactOnExport: redactOnExport,
                redactedHeaders: redactedHeaders,
                redactedQueryParams: redactedQueryParams,
              ))
          .toList(),
    };
  }

  /// Convenience alias for [toMap] — matches the [HarExporter] naming.
  static Map<String, Object?> fromRecords(
    List<RequestRecord> records, {
    String collectionName = 'Interceptly Export',
    bool redactOnExport = false,
    Set<String>? redactedHeaders,
    Set<String>? redactedQueryParams,
  }) =>
      toMap(
        records,
        collectionName: collectionName,
        redactOnExport: redactOnExport,
        redactedHeaders: redactedHeaders,
        redactedQueryParams: redactedQueryParams,
      );

  static Map<String, Object?> _itemFromRecord(
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

    final isMultipart =
        (r.requestContentType ?? '').contains('multipart/form-data');
    final isMultipartEmpty = isMultipart &&
        (r.requestBodyBytes == null || r.requestBodyBytes!.isEmpty) &&
        (r.requestBodyPreview == null || r.requestBodyPreview!.isEmpty);

    String? description;
    if (uri != null && uri.userInfo.isNotEmpty) {
      description =
          'Note: Userinfo credentials stripped from URL for security.';
    }
    if (isMultipartEmpty) {
      description = description == null
          ? 'Warning: Multipart body is empty or could not be reconstructed.'
          : '$description\nWarning: Multipart body is empty or could not be reconstructed.';
    }

    return {
      'name': '${r.method} ${uri?.path ?? effectiveUrl}',
      'request': {
        'method': r.method,
        'header': _mapHeaders(effectiveReqHeaders),
        'body': _buildBody(r),
        'url': _buildUrl(effectiveUrl, uri),
        if (description != null) 'description': description,
      },
      'response': <Object>[],
    };
  }

  static List<Map<String, String>> _mapHeaders(Map<String, String> headers) {
    return mapHeaderEntries(headers, keyName: 'key', valueName: 'value');
  }

  static Map<String, Object?>? _buildBody(RequestRecord r) {
    final contentType = r.requestContentType ?? '';

    if (contentType.contains('multipart/form-data')) {
      final hasBytes =
          r.requestBodyBytes != null && r.requestBodyBytes!.isNotEmpty;
      final hasPreview =
          r.requestBodyPreview != null && r.requestBodyPreview!.isNotEmpty;
      if (!hasBytes && !hasPreview) {
        return {
          'mode': 'formdata',
          'formdata': <Map<String, Object?>>[
            {
              'key': 'warning',
              'value': 'Multipart body preview unavailable or empty',
              'type': 'text',
              'disabled': true,
            },
          ],
        };
      }
      return {
        'mode': 'formdata',
        'formdata': <Map<String, Object?>>[
          {
            'key': 'warning',
            'value': 'Multipart body payload preserved from capture',
            'type': 'text',
            'disabled': true,
          },
        ],
      };
    }

    String? body;
    if (r.requestBodyBytes != null && r.requestBodyBytes!.isNotEmpty) {
      try {
        body = utf8.decode(r.requestBodyBytes!);
      } catch (_) {
        body = r.requestBodyPreview;
      }
    } else {
      body = r.requestBodyPreview;
    }

    if (body == null || body.isEmpty || BodyDecodeService.isPlaceholder(body)) {
      return null;
    }

    if (contentType.contains('application/x-www-form-urlencoded')) {
      return {'mode': 'urlencoded', 'urlencoded': _parseUrlEncoded(body)};
    }

    return {
      'mode': 'raw',
      'raw': body,
      'options': {
        'raw': {'language': _rawLanguage(contentType)},
      },
    };
  }

  static String _rawLanguage(String contentType) {
    if (contentType.contains('json')) return 'json';
    if (contentType.contains('xml')) return 'xml';
    if (contentType.contains('html')) return 'html';
    return 'text';
  }

  static List<Map<String, String>> _parseUrlEncoded(String body) {
    try {
      return Uri.splitQueryString(
        body,
      ).entries.map((e) => {'key': e.key, 'value': e.value}).toList();
    } catch (_) {
      return [];
    }
  }

  static Map<String, Object?> _buildUrl(String rawUrl, Uri? uri) {
    if (uri == null) {
      return {'raw': rawUrl};
    }

    final hasUserInfo = uri.userInfo.isNotEmpty;
    final sanitizedUri = hasUserInfo ? uri.replace(userInfo: '') : uri;
    final sanitizedRaw = hasUserInfo && rawUrl.contains('@')
        ? rawUrl.replaceFirst('${uri.userInfo}@', '')
        : rawUrl;

    final host =
        sanitizedUri.host.split('.').where((s) => s.isNotEmpty).toList();
    final pathSegments =
        sanitizedUri.pathSegments.where((s) => s.isNotEmpty).toList();
    final queryParams = sanitizedUri.queryParametersAll.entries
        .expand((e) => e.value.map((v) => {'key': e.key, 'value': v}))
        .toList();

    return {
      'raw': sanitizedRaw,
      'protocol': sanitizedUri.scheme,
      'host': host,
      if (sanitizedUri.hasPort) 'port': sanitizedUri.port.toString(),
      'path': pathSegments,
      if (queryParams.isNotEmpty) 'query': queryParams,
    };
  }
}
