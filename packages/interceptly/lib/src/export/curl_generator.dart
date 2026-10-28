import 'dart:convert';

import '../model/request_record.dart';
import '../engine/body_decode_service.dart';

/// Builds cURL commands from captured request records.
///
/// Bodies containing control characters use ANSI-C `$'...'` quoting
/// to remain executable.
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
    final sanitizedMethod =
        record.method.replaceAll(RegExp(r'[\r\n]'), '').trim().toUpperCase();

    if (!_allowedMethods.contains(sanitizedMethod)) {
      throw ArgumentError(
        'Invalid or unsafe HTTP method: "${record.method}". '
        'Only standard HTTP methods are allowed.',
      );
    }

    final sanitizedUrl = record.url.replaceAll(RegExp(r'[\r\n]'), '').trim();

    final buffer = StringBuffer();
    if (record.requestTruncation.hasDataLoss) {
      buffer.write(
        '# WARNING: Request body was truncated during capture '
        '(${record.requestTruncation.retainedBytes}/${record.requestSizeBytes} bytes)\n',
      );
    }
    buffer.write('curl');
    buffer.write(" -X '$sanitizedMethod'");

    for (final entry in record.requestHeaders.entries) {
      final key = entry.key.replaceAll(RegExp(r'[\r\n]'), '').trim();
      final rawValue = entry.value.replaceAll(RegExp(r'[\r\n]'), '');
      if (key.isEmpty) continue;
      buffer.write(' -H ${_shellQuote('$key: $rawValue')}');
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
      buffer.write(' --data-raw ${_shellQuote(body)}');
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

    buffer.write(' ${_shellQuote(sanitizedUrl)}');
    return buffer.toString();
  }

  /// Wraps [value] in single quotes or ANSI-C `$'...'` when control
  /// characters are present so multi-line bodies remain shell-safe.
  static String _shellQuote(String value) {
    if (_needsAnsiC(value)) {
      return "\$'${_escapeAnsiC(value)}'";
    }
    return "'${_escapeShell(value)}'";
  }

  /// Reports whether [value] requires ANSI-C quoting for safe shell export.
  static bool _needsAnsiC(String value) {
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      if (c == 10 || c == 13 || c == 0) return true;
      if (c < 32 || c == 127) return true;
    }
    return false;
  }

  /// Escapes [value] for inclusion inside ANSI-C `$'...'` quoting.
  static String _escapeAnsiC(String value) {
    final out = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      switch (c) {
        case 92:
          out.write(r'\\');
          break;
        case 39:
          out.write(r"\'");
          break;
        case 10:
          out.write(r'\n');
          break;
        case 13:
          out.write(r'\r');
          break;
        case 9:
          out.write(r'\t');
          break;
        case 0:
          out.write(r'\0');
          break;
        default:
          if (c < 32 || c == 127) {
            out.write('\\x${c.toRadixString(16).padLeft(2, '0')}');
          } else {
            out.writeCharCode(c);
          }
      }
    }
    return out.toString();
  }

  static String _escapeShell(String value) => value.replaceAll("'", "'\\''");
}
