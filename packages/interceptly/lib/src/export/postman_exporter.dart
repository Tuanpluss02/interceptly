import 'dart:convert';

import '../engine/body_decode_service.dart';
import '../model/request_record.dart';

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
      jsonEncode(toMap(
        records,
        collectionName: collectionName,
      ));

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
      'name': '${r.method} ${uri?.path ?? r.url}',
      'request': {
        'method': r.method,
        'header': _mapHeaders(r.requestHeaders),
        'body': _buildBody(r),
        'url': _buildUrl(r.url, uri),
        if (description != null) 'description': description,
      },
      'response': <Object>[],
    };
  }

  static List<Map<String, String>> _mapHeaders(Map<String, String> headers) {
    return headers.entries
        .map((entry) => {'key': entry.key, 'value': entry.value})
        .toList();
  }

  static Map<String, Object?>? _buildBody(RequestRecord r) {
    final contentType = r.requestContentType ?? '';

    if (contentType.contains('multipart/form-data')) {
      String? rawMultipart;
      if (r.requestBodyBytes != null && r.requestBodyBytes!.isNotEmpty) {
        try {
          rawMultipart = utf8.decode(r.requestBodyBytes!);
        } catch (_) {}
      }
      rawMultipart ??= (r.requestBodyPreview != null &&
              !BodyDecodeService.isPlaceholder(r.requestBodyPreview!) &&
              !r.requestBodyPreview!.startsWith('[binary:'))
          ? r.requestBodyPreview
          : null;

      if (rawMultipart != null && rawMultipart.isNotEmpty) {
        return {
          'mode': 'raw',
          'raw': rawMultipart,
          'options': {
            'raw': {'language': 'text'},
          },
        };
      }
      return {
        'mode': 'formdata',
        'formdata': <Map<String, Object?>>[
          {
            'key': 'warning',
            'value': 'Multipart body preview unavailable or binary',
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

    if (body == null ||
        body.isEmpty ||
        BodyDecodeService.isPlaceholder(body) ||
        body.startsWith('[binary:')) {
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
