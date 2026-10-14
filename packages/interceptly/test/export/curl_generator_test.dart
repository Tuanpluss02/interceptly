import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/export/curl_generator.dart';
import 'package:interceptly/src/model/request_record.dart';

void main() {
  group('CurlGenerator method quoting', () {
    test('quotes GET method in cURL command', () {
      final record = _record(method: 'GET', url: 'https://api.example.com/users');
      final curl = CurlGenerator.fromRecord(record);
      expect(curl, contains("-X 'GET'"));
      expect(curl, startsWith("curl -X 'GET' 'https://api.example.com/users'"));
    });

    test('quotes POST method in cURL command', () {
      final record = _record(
        method: 'POST',
        url: 'https://api.example.com/items',
        requestBodyPreview: '{"name":"item1"}',
      );
      final curl = CurlGenerator.fromRecord(record);
      expect(curl, contains("-X 'POST'"));
      expect(curl, startsWith("curl -X 'POST'"));
      expect(curl, contains("'https://api.example.com/items'"));
    });

    test('quotes other HTTP methods (PUT, DELETE, PATCH, HEAD, OPTIONS)', () {
      for (final method in ['PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS']) {
        final record = _record(method: method, url: 'https://api.example.com/resource');
        final curl = CurlGenerator.fromRecord(record);
        expect(curl, contains("-X '$method'"));
      }
    });
  });
}

RequestRecord _record({
  String method = 'GET',
  String url = 'https://api.example.com/test',
  int statusCode = 200,
  Map<String, String>? requestHeaders,
  Map<String, String>? responseHeaders,
  String? requestBodyPreview,
  String? responseBodyPreview,
}) {
  return RequestRecord(
    id: 'test-id',
    method: method,
    url: url,
    statusCode: statusCode,
    durationMs: 50,
    requestSizeBytes: 0,
    responseSizeBytes: 0,
    timestamp: DateTime(2026, 1, 1),
    requestHeaders: requestHeaders ?? {},
    responseHeaders: responseHeaders ?? {},
    requestBodyPreview: requestBodyPreview,
    responseBodyPreview: responseBodyPreview,
  );
}
