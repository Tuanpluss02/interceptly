import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/export/curl_generator.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/request_record.dart';

void main() {
  group('CurlGenerator method quoting', () {
    test('quotes GET method in cURL command', () {
      final record =
          _record(method: 'GET', url: 'https://api.example.com/users');
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
        final record =
            _record(method: method, url: 'https://api.example.com/resource');
        final curl = CurlGenerator.fromRecord(record);
        expect(curl, contains("-X '$method'"));
      }
    });
  });

  group('CurlGenerator data loss awareness', () {
    test(
        'prepends warning comment when request body was truncated at storage stage',
        () {
      final record = _record(
        method: 'POST',
        url: 'https://api.example.com/items',
        requestSizeBytes: 4096,
        requestBodyPreview: '{"name":"item1"}',
        requestTruncation: const BodyTruncation(
          originalBytes: 4096,
          retainedBytes: 1024,
          stage: TruncationStage.storage,
        ),
      );
      final curl = CurlGenerator.fromRecord(record);
      expect(
        curl,
        startsWith(
          '# WARNING: Request body was truncated during capture (1024/4096 bytes)\ncurl ',
        ),
      );
    });

    test(
        'prepends warning comment when request body was truncated at storageAndPreview stage',
        () {
      final record = _record(
        method: 'POST',
        url: 'https://api.example.com/items',
        requestSizeBytes: 4096,
        requestBodyPreview: '{"name":"item1"}',
        requestTruncation: const BodyTruncation(
          originalBytes: 4096,
          retainedBytes: 512,
          stage: TruncationStage.storageAndPreview,
        ),
      );
      final curl = CurlGenerator.fromRecord(record);
      expect(
        curl,
        startsWith(
          '# WARNING: Request body was truncated during capture (512/4096 bytes)\ncurl ',
        ),
      );
    });

    test(
        'does not prepend warning comment when request body was not truncated with data loss',
        () {
      final record = _record(
        method: 'POST',
        url: 'https://api.example.com/items',
        requestSizeBytes: 100,
        requestBodyPreview: '{"name":"item1"}',
        requestTruncation: const BodyTruncation.complete(100),
      );
      final curl = CurlGenerator.fromRecord(record);
      expect(curl, isNot(contains('# WARNING: Request body was truncated')));
      expect(curl, startsWith("curl -X 'POST'"));
    });

    test('does not prepend warning comment when preview only (no data loss)',
        () {
      final record = _record(
        method: 'POST',
        url: 'https://api.example.com/items',
        requestSizeBytes: 1000,
        requestBodyPreview: '{"name":"item1"}',
        requestTruncation: const BodyTruncation(
          originalBytes: 1000,
          retainedBytes: 100,
          stage: TruncationStage.preview,
        ),
      );
      final curl = CurlGenerator.fromRecord(record);
      expect(curl, isNot(contains('# WARNING: Request body was truncated')));
      expect(curl, startsWith("curl -X 'POST'"));
    });
  });
}

RequestRecord _record({
  String method = 'GET',
  String url = 'https://api.example.com/test',
  int statusCode = 200,
  int requestSizeBytes = 0,
  BodyTruncation requestTruncation = const BodyTruncation.complete(0),
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
    requestSizeBytes: requestSizeBytes,
    responseSizeBytes: 0,
    timestamp: DateTime(2026, 1, 1),
    requestHeaders: requestHeaders ?? {},
    responseHeaders: responseHeaders ?? {},
    requestBodyPreview: requestBodyPreview,
    responseBodyPreview: responseBodyPreview,
    requestTruncation: requestTruncation,
  );
}
