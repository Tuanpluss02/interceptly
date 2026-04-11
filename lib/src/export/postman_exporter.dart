import 'dart:convert';

import '../model/request_record.dart';
import '../session/body_decode_service.dart';

/// Exports captured request records to Postman Collection v2.1 format.
///
/// The generated JSON can be imported directly into Postman via
/// File → Import → Raw text / file.
class PostmanExporter {
  const PostmanExporter._();

  /// Converts [records] into a Postman Collection v2.1 JSON string.
  static String toJson(
    List<RequestRecord> records, {
    String collectionName = 'Interceptly Export',
  }) =>
      jsonEncode(toMap(records, collectionName: collectionName));

  /// Converts [records] into a Postman Collection v2.1 root object.
  static Map<String, Object?> toMap(
    List<RequestRecord> records, {
    String collectionName = 'Interceptly Export',
  }) {
    return {
      'info': {
        'name': collectionName,
        'schema':
            'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
      },
      'item': records.map(_itemFromRecord).toList(),
    };
  }

  static Map<String, Object?> _itemFromRecord(RequestRecord r) {
    final uri = Uri.tryParse(r.url);

    return {
      'name': '${r.method} ${uri?.path ?? r.url}',
      'request': {
        'method': r.method,
        'header': _mapHeaders(r.requestHeaders),
        'body': _buildBody(r),
        'url': _buildUrl(r.url, uri),
      },
      'response': [],
    };
  }

  static List<Map<String, String>> _mapHeaders(Map<String, String> headers) {
    return headers.entries
        .map((e) => {'key': e.key, 'value': e.value})
        .toList();
  }

  static Map<String, Object?>? _buildBody(RequestRecord r) {
    final body = r.requestBodyPreview;
    if (body == null || body.isEmpty || BodyDecodeService.isPlaceholder(body)) {
      return null;
    }

    final contentType = r.requestContentType ?? '';

    if (contentType.contains('application/x-www-form-urlencoded')) {
      return {'mode': 'urlencoded', 'urlencoded': _parseUrlEncoded(body)};
    }

    if (contentType.contains('multipart/form-data')) {
      return {'mode': 'formdata', 'formdata': <Object>[]};
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

    final host = uri.host.split('.');
    final pathSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final queryParams = uri.queryParametersAll.entries
        .expand((e) => e.value.map((v) => {'key': e.key, 'value': v}))
        .toList();

    return {
      'raw': rawUrl,
      'protocol': uri.scheme,
      'host': host,
      'path': pathSegments,
      if (queryParams.isNotEmpty) 'query': queryParams,
    };
  }
}
