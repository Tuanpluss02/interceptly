import 'dart:convert';

import '../capture/capture_guard.dart';
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

  /// Converts a [RequestRecord] into a shell-safe cURL command.
  ///
  /// Throws an [ArgumentError] if the HTTP method is non-standard or contains
  /// unsafe characters (such as CRLF or shell metacharacters).
  ///
  /// When [redactOnExport] is true, sensitive headers and query parameters
  /// will be masked with `[REDACTED]`.
  static String fromRecord(
    RequestRecord record, {
    bool redactOnExport = false,
    Set<String>? redactedHeaders,
    Set<String>? redactedQueryParams,
  }) {
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

    final effectiveHeaders = redactOnExport
        ? CaptureGuard.redactHeaders(
            record.requestHeaders,
            (redactedHeaders ?? _defaultRedactedHeaders)
                .map((h) => h.toLowerCase())
                .toSet(),
          )
        : (redactedHeaders != null && redactedHeaders.isNotEmpty
            ? CaptureGuard.redactHeaders(
                record.requestHeaders,
                redactedHeaders.map((h) => h.toLowerCase()).toSet(),
              )
            : record.requestHeaders);

    final rawUrl = redactOnExport
        ? CaptureGuard.sanitizeUrl(
            record.url,
            (redactedQueryParams ?? _defaultRedactedQueryParams)
                .map((q) => q.toLowerCase())
                .toSet(),
          )
        : (redactedQueryParams != null && redactedQueryParams.isNotEmpty
            ? CaptureGuard.sanitizeUrl(
                record.url,
                redactedQueryParams.map((q) => q.toLowerCase()).toSet(),
              )
            : record.url);

    final sanitizedUrl = rawUrl.replaceAll(RegExp(r'[\r\n]'), '').trim();

    final buffer = StringBuffer('curl');
    buffer.write(' -X $sanitizedMethod');

    for (final entry in effectiveHeaders.entries) {
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

    final acceptEncoding = effectiveHeaders.entries
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
