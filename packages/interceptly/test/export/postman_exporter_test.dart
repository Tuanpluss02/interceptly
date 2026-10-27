import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/export/postman_exporter.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/request_record.dart';

void main() {
  group('PostmanExporter', () {
    RequestRecord createRecord({
      String method = 'POST',
      String url = 'https://api.example.com/upload',
      Map<String, String>? requestHeaders,
      Uint8List? requestBodyBytes,
      String? requestBodyPreview,
    }) {
      final headers = requestHeaders ??
          {
            'content-type':
                'multipart/form-data; boundary=----WebKitFormBoundaryXYZ',
          };
      final contentType = headers['content-type'];
      return RequestRecord(
        id: 'test_rec_1',
        method: method,
        url: url,
        statusCode: 200,
        durationMs: 42,
        requestSizeBytes:
            requestBodyBytes?.length ?? requestBodyPreview?.length ?? 0,
        responseSizeBytes: 0,
        timestamp: DateTime(2026, 10, 28, 12, 0, 0),
        requestHeaders: headers,
        responseHeaders: const {},
        requestContentType: contentType,
        requestBodyBytes: requestBodyBytes,
        requestBodyPreview: requestBodyPreview,
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation.complete(0),
      );
    }

    test('exports UTF-8 multipart/form-data as mode: raw with text language',
        () {
      const boundary = '----WebKitFormBoundaryXYZ';
      const multipartBody = '--$boundary\r\n'
          'Content-Disposition: form-data; name="username"\r\n\r\n'
          'alice\r\n'
          '--$boundary--\r\n';
      final record = createRecord(
        requestBodyBytes: Uint8List.fromList(utf8.encode(multipartBody)),
      );

      final map = PostmanExporter.toMap([record]);
      final items = map['item'] as List<dynamic>;
      expect(items, hasLength(1));

      final request = (items.first as Map<String, dynamic>)['request']
          as Map<String, dynamic>;
      final body = request['body'] as Map<String, dynamic>;

      expect(body['mode'], equals('raw'));
      expect(body['raw'], equals(multipartBody));
      expect(
          body['options'],
          equals({
            'raw': {'language': 'text'},
          }));
    });

    test(
        'exports multipart with warning item when body is binary or unavailable',
        () {
      final record = createRecord(
        requestBodyBytes:
            Uint8List.fromList([0x00, 0xFF, 0xFE, 0x01]), // Invalid UTF-8
        requestBodyPreview: '[binary: 4 bytes]',
      );

      final map = PostmanExporter.toMap([record]);
      final items = map['item'] as List<dynamic>;
      final request = (items.first as Map<String, dynamic>)['request']
          as Map<String, dynamic>;
      final body = request['body'] as Map<String, dynamic>;

      expect(body['mode'], equals('formdata'));
      final formdata = body['formdata'] as List<dynamic>;
      expect(formdata, hasLength(1));
      expect(
          formdata.first,
          equals({
            'key': 'warning',
            'value': 'Multipart body preview unavailable or binary',
            'type': 'text',
            'disabled': true,
          }));
    });

    test('strips userinfo credentials from URL and notes in description', () {
      final record = createRecord(
        url: 'https://admin:supersecret@api.example.com/secure/resource',
        requestHeaders: {'content-type': 'application/json'},
        requestBodyPreview: '{"key": "value"}',
      );

      final map = PostmanExporter.toMap([record]);
      final items = map['item'] as List<dynamic>;
      final request = (items.first as Map<String, dynamic>)['request']
          as Map<String, dynamic>;

      final url = request['url'] as Map<String, dynamic>;
      expect(url['raw'], equals('https://api.example.com/secure/resource'));
      expect(request['description'],
          contains('Userinfo credentials stripped from URL for security.'));
    });

    test('exports urlencoded payload correctly', () {
      final record = createRecord(
        url: 'https://api.example.com/login',
        requestHeaders: {'content-type': 'application/x-www-form-urlencoded'},
        requestBodyPreview: 'username=bob&grant_type=password',
      );

      final map = PostmanExporter.toMap([record]);
      final items = map['item'] as List<dynamic>;
      final request = (items.first as Map<String, dynamic>)['request']
          as Map<String, dynamic>;
      final body = request['body'] as Map<String, dynamic>;

      expect(body['mode'], equals('urlencoded'));
      final urlencoded = body['urlencoded'] as List<dynamic>;
      expect(
          urlencoded,
          containsAll([
            {'key': 'username', 'value': 'bob'},
            {'key': 'grant_type', 'value': 'password'},
          ]));
    });

    test('toJson produces valid JSON string', () {
      final record = createRecord(
        url: 'https://api.example.com/test',
        requestHeaders: {'content-type': 'application/json'},
        requestBodyPreview: '{"hello": "world"}',
      );

      final jsonStr =
          PostmanExporter.toJson([record], collectionName: 'My Tests');
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect((decoded['info'] as Map<String, dynamic>)['name'],
          equals('My Tests'));
    });
  });
}
