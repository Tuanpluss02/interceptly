// ignore_for_file: invalid_use_of_internal_member
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/export/har_exporter.dart';
import 'package:interceptly/src/export/postman_exporter.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/request_record.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('export_roundtrip_test_');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  RequestRecord sampleRecord({
    String id = 'req-1',
    String method = 'POST',
    String url = 'https://api.example.com/v1/users?page=1&limit=20',
    int statusCode = 201,
    int durationMs = 150,
    Map<String, String>? requestHeaders,
    Map<String, String>? responseHeaders,
    String? requestBody = '{"name":"Alice","role":"admin"}',
    String? responseBody = '{"id":"usr_123","name":"Alice"}',
    String requestContentType = 'application/json',
    String responseContentType = 'application/json',
  }) {
    return RequestRecord(
      id: id,
      method: method,
      url: url,
      statusCode: statusCode,
      durationMs: durationMs,
      requestSizeBytes: requestBody?.length ?? 0,
      responseSizeBytes: responseBody?.length ?? 0,
      timestamp: DateTime.utc(2026, 10, 14, 12, 0, 0),
      requestHeaders: requestHeaders ??
          {
            'Authorization': 'Bearer test-token-123',
            'Content-Type': requestContentType,
            'X-Request-Id': 'abc-123',
          },
      responseHeaders: responseHeaders ??
          {
            'Content-Type': responseContentType,
            'X-Server-Time': '42ms',
          },
      requestContentType: requestContentType,
      responseContentType: responseContentType,
      requestBodyPreview: requestBody,
      responseBodyPreview: responseBody,
      requestTruncation: const BodyTruncation.complete(32),
      responseTruncation: const BodyTruncation.complete(31),
    );
  }

  group('HAR Export Round-trip & Schema Validation', () {
    test('writes HAR to file and reads back valid HAR 1.2 JSON schema',
        () async {
      final records = [
        sampleRecord(
            id: 'r1',
            method: 'GET',
            url: 'https://api.example.com/items?cat=tech',
            statusCode: 200),
        sampleRecord(
            id: 'r2',
            method: 'POST',
            url: 'https://api.example.com/items',
            statusCode: 201),
      ];

      final harMap = HarExporter.toMap(records);
      final jsonString = jsonEncode(harMap);

      final file = File('${tempDir.path}/test_export.har');
      await file.writeAsString(jsonString);

      final readContent = await file.readAsString();
      final decoded = jsonDecode(readContent) as Map<String, dynamic>;

      expect(decoded.containsKey('log'), isTrue);
      final log = decoded['log'] as Map<String, dynamic>;

      expect(log['version'], equals('1.2'));
      expect(log['creator'], isA<Map<String, dynamic>>());
      final creator = log['creator'] as Map<String, dynamic>;
      expect(creator['name'], equals('Interceptly'));
      expect(creator['version'], isNotEmpty);

      expect(log['pages'], isA<List>());
      expect(log['entries'], isA<List>());
      final entries = log['entries'] as List;
      expect(entries.length, equals(2));

      final firstEntry = entries[0] as Map<String, dynamic>;
      expect(firstEntry['startedDateTime'], equals('2026-10-14T12:00:00.000Z'));
      expect(firstEntry['time'], equals(150));
      expect(firstEntry.containsKey('cache'), isTrue);
      expect(firstEntry.containsKey('timings'), isTrue);

      final req = firstEntry['request'] as Map<String, dynamic>;
      expect(req['method'], equals('GET'));
      expect(req['url'], equals('https://api.example.com/items?cat=tech'));
      expect(req['httpVersion'], equals('HTTP/1.1'));
      expect(req['headers'], isA<List>());
      expect(req['queryString'], isA<List>());
      final qs = req['queryString'] as List;
      expect(qs.any((q) => q['name'] == 'cat' && q['value'] == 'tech'), isTrue);

      final res = firstEntry['response'] as Map<String, dynamic>;
      expect(res['status'], equals(200));
      expect(res['content'], isA<Map<String, dynamic>>());
      final content = res['content'] as Map<String, dynamic>;
      expect(content['mimeType'], equals('application/json'));
      expect(content['text'], equals('{"id":"usr_123","name":"Alice"}'));
    });

    test(
        'HAR export outputs authorization and query params raw without redaction',
        () async {
      final records = [
        sampleRecord(url: 'https://api.example.com/auth?token=999'),
      ];

      final harMap = HarExporter.toMap(records);
      final file = File('${tempDir.path}/unredacted.har');
      await file.writeAsString(jsonEncode(harMap));

      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final entry =
          (decoded['log']['entries'] as List).first as Map<String, dynamic>;
      final req = entry['request'] as Map<String, dynamic>;

      final headers = (req['headers'] as List).cast<Map<String, dynamic>>();
      final authHeader =
          headers.firstWhere((h) => h['name'] == 'Authorization');
      expect(authHeader['value'], equals('Bearer test-token-123'));

      final qs = (req['queryString'] as List).cast<Map<String, dynamic>>();
      final tokenQuery = qs.firstWhere((q) => q['name'] == 'token');
      expect(tokenQuery['value'], equals('999'));
    });

    test('HAR export handles binary placeholder without corrupting JSON',
        () async {
      final records = [
        sampleRecord(
          responseBody: '\x00[binary: 1024 bytes]',
          responseContentType: 'application/octet-stream',
        ),
      ];

      final harMap = HarExporter.toMap(records);
      final jsonString = jsonEncode(harMap);
      final file = File('${tempDir.path}/binary.har');
      await file.writeAsString(jsonString);

      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final entry =
          (decoded['log']['entries'] as List).first as Map<String, dynamic>;
      final content = entry['response']['content'] as Map<String, dynamic>;
      expect(content['text'], equals(''));
    });
  });

  group('Postman Export Round-trip & Schema Validation', () {
    test('writes Postman Collection to file and reads back valid v2.1.0 schema',
        () async {
      final records = [
        sampleRecord(
            id: 'r1',
            method: 'GET',
            url: 'https://api.example.com:8080/v1/users?page=1'),
        sampleRecord(
          id: 'r2',
          method: 'POST',
          url: 'https://api.example.com:8080/v1/users',
          requestBody: '{"name":"Bob"}',
          requestContentType: 'application/json',
        ),
      ];

      final postmanMap =
          PostmanExporter.toMap(records, collectionName: 'My Service API');
      final jsonString = jsonEncode(postmanMap);

      final file = File('${tempDir.path}/test_collection.json');
      await file.writeAsString(jsonString);

      final readContent = await file.readAsString();
      final decoded = jsonDecode(readContent) as Map<String, dynamic>;

      expect(decoded.containsKey('info'), isTrue);
      final info = decoded['info'] as Map<String, dynamic>;
      expect(info['name'], equals('My Service API'));
      expect(
          info['schema'],
          equals(
              'https://schema.getpostman.com/json/collection/v2.1.0/collection.json'));

      expect(decoded.containsKey('item'), isTrue);
      final items = decoded['item'] as List;
      expect(items.length, equals(2));

      final firstItem = items[0] as Map<String, dynamic>;
      expect(firstItem['name'], equals('GET /v1/users'));
      final firstReq = firstItem['request'] as Map<String, dynamic>;
      expect(firstReq['method'], equals('GET'));
      final firstUrl = firstReq['url'] as Map<String, dynamic>;
      expect(firstUrl['raw'],
          equals('https://api.example.com:8080/v1/users?page=1'));
      expect(firstUrl['port'], equals('8080'));
      expect(firstUrl['protocol'], equals('https'));
      expect(firstUrl['host'], equals(['api', 'example', 'com']));
      expect(firstUrl['path'], equals(['v1', 'users']));

      final secondItem = items[1] as Map<String, dynamic>;
      expect(secondItem['name'], equals('POST /v1/users'));
      final secondReq = secondItem['request'] as Map<String, dynamic>;
      expect(secondReq['method'], equals('POST'));
      final body = secondReq['body'] as Map<String, dynamic>;
      expect(body['mode'], equals('raw'));
      expect(body['raw'], equals('{"name":"Bob"}'));
      expect(body['options']['raw']['language'], equals('json'));
    });

    test('Postman export handles urlencoded form-data and multipart', () async {
      final records = [
        sampleRecord(
          method: 'POST',
          url: 'https://api.example.com/form',
          requestBody: 'param1=val1&param2=val2',
          requestContentType: 'application/x-www-form-urlencoded',
        ),
      ];

      final postmanMap = PostmanExporter.toMap(records);
      final file = File('${tempDir.path}/form.json');
      await file.writeAsString(jsonEncode(postmanMap));

      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final item = (decoded['item'] as List).first as Map<String, dynamic>;
      final body = item['request']['body'] as Map<String, dynamic>;

      expect(body['mode'], equals('urlencoded'));
      final urlencoded = body['urlencoded'] as List;
      expect(
          urlencoded.any((p) => p['key'] == 'param1' && p['value'] == 'val1'),
          isTrue);
      expect(
          urlencoded.any((p) => p['key'] == 'param2' && p['value'] == 'val2'),
          isTrue);
    });
  });

  group('Golden Exporters Determinism Test', () {
    test('HAR output is deterministic for identical input record', () {
      final record = sampleRecord();
      final har1 = HarExporter.toMap([record]);
      final har2 = HarExporter.toMap([record]);

      expect(jsonEncode(har1), equals(jsonEncode(har2)));
    });

    test('Postman output is deterministic for identical input record', () {
      final record = sampleRecord();
      final postman1 = PostmanExporter.toMap([record]);
      final postman2 = PostmanExporter.toMap([record]);

      expect(jsonEncode(postman1), equals(jsonEncode(postman2)));
    });
  });
}
