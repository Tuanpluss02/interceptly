import '../model/request_record.dart';
import '../session/body_decode_service.dart';

/// Builds cURL commands from captured request records.
class CurlGenerator {
  const CurlGenerator._();

  /// Converts a [RequestRecord] into a shell-safe cURL command.
  static String fromRecord(RequestRecord record) {
    final buffer = StringBuffer('curl');

    buffer.write(' -X ${record.method}');

    for (final entry in record.requestHeaders.entries) {
      buffer.write(" -H '${_escapeShell('${entry.key}: ${entry.value}')}'");
    }

    final body = record.requestBodyPreview;
    if (body != null && body.isNotEmpty && !BodyDecodeService.isPlaceholder(body)) {
      buffer.write(" --data-raw '${_escapeShell(body)}'");
    }

    final acceptEncoding = record.requestHeaders['accept-encoding'];
    if (acceptEncoding != null && acceptEncoding.contains('gzip')) {
      buffer.write(' --compressed');
    }

    buffer.write(" '${_escapeShell(record.url)}'");
    return buffer.toString();
  }

  static String _escapeShell(String value) => value.replaceAll("'", "'\\''");
}
