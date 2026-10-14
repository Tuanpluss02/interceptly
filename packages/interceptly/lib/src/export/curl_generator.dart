import 'dart:convert';

import '../model/request_record.dart';
import '../session/body_decode_service.dart';

/// Builds cURL commands from captured request records.
class CurlGenerator {
  const CurlGenerator._();

  /// Whitelisted standard HTTP methods for safe shell export.
  static const Set<String> _allowedMethods = {
    'GET',
    'POST',
    'PUT',
    'DELETE',
    'PATCH',
    'HEAD',
    'OPTIONS',
    'TRACE',
    'CONNECT',
  };

  /// Converts a [RequestRecord] into a shell-safe cURL command.
  ///
  /// Throws an [ArgumentError] if the HTTP method is non-standard or contains
  /// unsafe characters (such as CRLF or shell metacharacters).
  static String fromRecord(RequestRecord record) {
    final sanitizedMethod = record.method
        .replaceAll(RegExp(r'[\r\n]'), '')
        .trim()
        .toUpperCase();

    if (!_allowedMethods.contains(sanitizedMethod)) {
      throw ArgumentError(
        'Invalid or unsafe HTTP method: "${record.method}". '
        'Only standard HTTP methods are allowed.',
      );
    }

    final sanitizedUrl = record.url.replaceAll(RegExp(r'[\r\n]'), '').trim();

    final buffer = StringBuffer('curl');
    buffer.write(" -X '$sanitizedMethod'");

    for (final entry in record.requestHeaders.entries) {
      final key = entry.key.replaceAll(RegExp(r'[\r\n]'), '').trim();
      final value = entry.value.replaceAll(RegExp(r'[\r\n]'), '');
      if (key.isEmpty) continue;
      buffer.write(" -H '${_escapeShell('$key: $value')}'");
    }

    String? body;
    if (record.requestBodyBytes != null &&
        record.requestBodyBytes!.isNotEmpty) {
      try {
        body = utf8.decode(record.requestBodyBytes!);
      } catch (_) {
        body = record.requestBodyPreview;
      }
    } else {
      body = record.requestBodyPreview;
    }

    if (body != null &&
        body.isNotEmpty &&
        !BodyDecodeService.isPlaceholder(body)) {
      buffer.write(" --data-raw '${_escapeShell(body)}'");
    }

    final acceptEncoding = record.requestHeaders.entries
        .firstWhere(
          (e) => e.key.toLowerCase() == 'accept-encoding',
          orElse: () => const MapEntry('', ''),
        )
        .value;
    if (acceptEncoding.isNotEmpty && acceptEncoding.contains('gzip')) {
      buffer.write(' --compressed');
    }

    buffer.write(" '${_escapeShell(sanitizedUrl)}'");
    return buffer.toString();
  }

  static String _escapeShell(String value) => value.replaceAll("'", "'\\''");
}
