import '../model/request_record.dart';

class CurlGenerator {
  const CurlGenerator._();

  static String fromRecord(RequestRecord record) {
    final buffer = StringBuffer('curl');

    buffer.write(' -X ${record.method}');

    for (final entry in record.requestHeaders.entries) {
      buffer.write(" -H '${entry.key}: ${entry.value}'");
    }

    final body = record.requestBodyPreview;
    if (body != null && body.isNotEmpty) {
      buffer.write(" --data '$body'");
    }

    buffer.write(" '${record.url}'");
    return buffer.toString();
  }
}
