import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/export/curl_generator.dart';
import 'package:interceptly/src/export/har_exporter.dart';
import 'package:interceptly/src/export/postman_exporter.dart';
import 'package:interceptly/src/model/request_record.dart';

void main() {
  // ── CurlGenerator ────────────────────────────────────────────────────────

  group('CurlGenerator', () {
    test('generates basic GET command', () {
      final cmd = CurlGenerator.fromRecord(_record(
        method: 'GET',
        url: 'https://api.example.com/users',
      ));
      expect(cmd, contains("curl -X GET"));
      expect(cmd, contains("'https://api.example.com/users'"));
    });

    test('includes headers as -H flags', () {
      final cmd = CurlGenerator.fromRecord(_record(
        requestHeaders: {
          'Authorization': 'Bearer token',
          'Content-Type': 'application/json',
        },
      ));
      expect(cmd, contains("-H 'Authorization: Bearer token'"));
      expect(cmd, contains("-H 'Content-Type: application/json'"));
    });

    test('includes body with --data-raw', () {
      final cmd = CurlGenerator.fromRecord(_record(
        requestBodyPreview: '{"name":"Alice"}',
      ));
      expect(cmd, contains("--data-raw '{\"name\":\"Alice\"}'"));
    });

    test('skips body when null', () {
      final cmd = CurlGenerator.fromRecord(_record(requestBodyPreview: null));
      expect(cmd, isNot(contains('--data-raw')));
    });

    test('skips body when body starts with [  (binary placeholder)', () {
      final cmd = CurlGenerator.fromRecord(_record(requestBodyPreview: '[binary: 100 bytes]'));
      expect(cmd, isNot(contains('--data-raw')));
    });

    test('adds --compressed when accept-encoding contains gzip', () {
      final cmd = CurlGenerator.fromRecord(_record(
        requestHeaders: {'accept-encoding': 'gzip, deflate'},
      ));
      expect(cmd, contains('--compressed'));
    });

    test('does not add --compressed without gzip header', () {
      final cmd = CurlGenerator.fromRecord(_record());
      expect(cmd, isNot(contains('--compressed')));
    });

    test('escapes single quotes in URL', () {
      final cmd = CurlGenerator.fromRecord(_record(url: "https://example.com/it's"));
      expect(cmd, contains("'https://example.com/it'\\''s'"));
    });

    test('escapes single quotes in header value', () {
      final cmd = CurlGenerator.fromRecord(_record(
        requestHeaders: {'X-Token': "it's"},
      ));
      expect(cmd, contains("'X-Token: it'\\''s'"));
    });
  });

  // ── HarExporter ──────────────────────────────────────────────────────────

  group('HarExporter', () {
    test('produces valid HAR root structure', () {
      final har = HarExporter.fromRecords([_record()]);
      expect(har.containsKey('log'), isTrue);
      final log = har['log'] as Map<String, Object?>;
      expect(log['version'], '1.2');
      expect(log.containsKey('creator'), isTrue);
      expect(log.containsKey('entries'), isTrue);
    });

    test('entry contains request and response blocks', () {
      final har = HarExporter.fromRecords([_record()]);
      final entry = (har['log'] as Map)['entries'] as List;
      expect(entry.length, 1);
      final e = entry.first as Map;
      expect(e.containsKey('request'), isTrue);
      expect(e.containsKey('response'), isTrue);
    });

    test('request block carries correct method and URL', () {
      final har = HarExporter.fromRecords([
        _record(method: 'POST', url: 'https://api.example.com/login'),
      ]);
      final req = ((har['log'] as Map)['entries'] as List).first as Map;
      expect((req['request'] as Map)['method'], 'POST');
      expect((req['request'] as Map)['url'], 'https://api.example.com/login');
    });

    test('response content.text is empty for binary placeholder', () {
      final har = HarExporter.fromRecords([
        _record(responseBodyPreview: '[binary: 512 bytes]'),
      ]);
      final entry = ((har['log'] as Map)['entries'] as List).first as Map;
      final content = (entry['response'] as Map)['content'] as Map;
      expect(content['text'], '');
    });

    test('response content.text carries decoded body', () {
      final har = HarExporter.fromRecords([
        _record(responseBodyPreview: '{"status":"ok"}'),
      ]);
      final entry = ((har['log'] as Map)['entries'] as List).first as Map;
      final content = (entry['response'] as Map)['content'] as Map;
      expect(content['text'], '{"status":"ok"}');
    });

    test('headers are mapped to name/value pairs', () {
      final har = HarExporter.fromRecords([
        _record(requestHeaders: {'Content-Type': 'application/json'}),
      ]);
      final req = ((har['log'] as Map)['entries'] as List).first as Map;
      final headers = (req['request'] as Map)['headers'] as List;
      expect(headers.first, {'name': 'Content-Type', 'value': 'application/json'});
    });

    test('empty records list produces empty entries', () {
      final har = HarExporter.fromRecords([]);
      final entries = (har['log'] as Map)['entries'] as List;
      expect(entries, isEmpty);
    });
  });

  // ── PostmanExporter ───────────────────────────────────────────────────────

  group('PostmanExporter', () {
    test('produces valid Postman collection root structure', () {
      final col = PostmanExporter.fromRecords([_record()]);
      expect(col.containsKey('info'), isTrue);
      expect(col.containsKey('item'), isTrue);
      final info = col['info'] as Map;
      expect(info['schema'], contains('v2.1.0'));
    });

    test('uses custom collection name', () {
      final col = PostmanExporter.fromRecords([], collectionName: 'My API');
      expect((col['info'] as Map)['name'], 'My API');
    });

    test('item name is METHOD /path', () {
      final col = PostmanExporter.fromRecords([
        _record(method: 'GET', url: 'https://api.example.com/users'),
      ]);
      final item = (col['item'] as List).first as Map;
      expect(item['name'], 'GET /users');
    });

    test('url block carries raw and parsed fields', () {
      final col = PostmanExporter.fromRecords([
        _record(url: 'https://api.example.com/users?page=1'),
      ]);
      final item = (col['item'] as List).first as Map;
      final url = (item['request'] as Map)['url'] as Map;
      expect(url['raw'], 'https://api.example.com/users?page=1');
      expect(url['protocol'], 'https');
      expect((url['host'] as List), ['api', 'example', 'com']);
      expect((url['path'] as List), ['users']);
      final query = url['query'] as List;
      expect(query.first, {'key': 'page', 'value': '1'});
    });

    test('raw body mode is used for JSON content type', () {
      final col = PostmanExporter.fromRecords([
        _record(
          requestBodyPreview: '{"name":"Alice"}',
          requestContentType: 'application/json',
        ),
      ]);
      final item = (col['item'] as List).first as Map;
      final body = (item['request'] as Map)['body'] as Map;
      expect(body['mode'], 'raw');
      expect((body['options'] as Map)['raw'], {'language': 'json'});
    });

    test('urlencoded body mode for form-encoded content type', () {
      final col = PostmanExporter.fromRecords([
        _record(
          requestBodyPreview: 'key=value&foo=bar',
          requestContentType: 'application/x-www-form-urlencoded',
        ),
      ]);
      final item = (col['item'] as List).first as Map;
      final body = (item['request'] as Map)['body'] as Map;
      expect(body['mode'], 'urlencoded');
      final urlencoded = body['urlencoded'] as List;
      expect(urlencoded, containsAll([
        {'key': 'key', 'value': 'value'},
        {'key': 'foo', 'value': 'bar'},
      ]));
    });

    test('formdata mode for multipart/form-data', () {
      final col = PostmanExporter.fromRecords([
        _record(
          requestBodyPreview: 'some content',
          requestContentType: 'multipart/form-data',
        ),
      ]);
      final item = (col['item'] as List).first as Map;
      final body = (item['request'] as Map)['body'] as Map;
      expect(body['mode'], 'formdata');
    });

    test('body is null when requestBodyPreview is null', () {
      final col = PostmanExporter.fromRecords([_record(requestBodyPreview: null)]);
      final item = (col['item'] as List).first as Map;
      expect((item['request'] as Map)['body'], isNull);
    });

    test('headers are mapped to key/value pairs', () {
      final col = PostmanExporter.fromRecords([
        _record(requestHeaders: {'Authorization': 'Bearer token'}),
      ]);
      final item = (col['item'] as List).first as Map;
      final headers = (item['request'] as Map)['header'] as List;
      expect(headers.first, {'key': 'Authorization', 'value': 'Bearer token'});
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
  String? requestContentType,
  String? responseContentType,
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
    requestContentType: requestContentType,
    responseContentType: responseContentType,
    requestBodyPreview: requestBodyPreview,
    responseBodyPreview: responseBodyPreview,
  );
}
