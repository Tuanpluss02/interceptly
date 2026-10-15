import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/capture/body_bytes.dart';

void main() {
  group('encodeBodyBytes', () {
    test('returns null when body is null', () {
      expect(encodeBodyBytes(null), isNull);
    });

    test('returns exact Uint8List when body is already Uint8List', () {
      final input = Uint8List.fromList([1, 2, 3, 4, 5]);
      final result = encodeBodyBytes(input);
      expect(result, isNotNull);
      expect(result, equals(input));
    });

    test('converts List<int> to Uint8List', () {
      final input = <int>[10, 20, 30];
      final result = encodeBodyBytes(input);
      expect(result, isA<Uint8List>());
      expect(result, equals(Uint8List.fromList(input)));
    });

    test('encodes String to UTF-8 bytes', () {
      const input = 'Interceptly test payload 🚀';
      final result = encodeBodyBytes(input);
      expect(result, isNotNull);
      expect(result, equals(Uint8List.fromList(utf8.encode(input))));
    });

    test('encodes JSON map to UTF-8 bytes', () {
      final input = {'status': 'ok', 'count': 42};
      final result = encodeBodyBytes(input);
      expect(result, isNotNull);
      final decoded = jsonDecode(utf8.decode(result!)) as Map<String, dynamic>;
      expect(decoded['status'], 'ok');
      expect(decoded['count'], 42);
    });

    test('encodes JSON list to UTF-8 bytes', () {
      final input = ['item1', 123, true];
      final result = encodeBodyBytes(input);
      expect(result, isNotNull);
      final decoded = jsonDecode(utf8.decode(result!)) as List<dynamic>;
      expect(decoded, equals(['item1', 123, true]));
    });

    test('falls back gracefully on non-encodable collections', () {
      final nonEncodable = {'date': DateTime.fromMillisecondsSinceEpoch(0)};
      final result = encodeBodyBytes(nonEncodable);
      expect(result, isNotNull);
      expect(result!.isNotEmpty, isTrue);
    });

    test('handles Stream placeholder without throwing', () {
      final stream = Stream<List<int>>.fromIterable([
        [1, 2, 3]
      ]);
      final result = encodeBodyBytes(stream);
      expect(result, isNotNull);
      expect(result!.isNotEmpty, isTrue);
    });

    test('falls back to toString for primitive or custom objects', () {
      final result = encodeBodyBytes(12345);
      expect(result, isNotNull);
      expect(utf8.decode(result!), '12345');
    });

    test('returns null if toString throws on custom object', () {
      final throwingObject = _ThrowingObject();
      final result = encodeBodyBytes(throwingObject);
      expect(result, isNull);
    });
  });

  group('header utilities', () {
    test('normalizeHeaders joins lists and stringifies entries', () {
      final raw = <String, Object?>{
        'content-type': 'application/json',
        'accept': ['text/html', 'application/xhtml+xml'],
        'x-count': 3,
      };
      final normalized = normalizeHeaders(raw);
      expect(normalized['content-type'], 'application/json');
      expect(normalized['accept'], 'text/html, application/xhtml+xml');
      expect(normalized['x-count'], '3');
    });

    test('normalizeHeaders joins set-cookie with newline instead of comma', () {
      final headers = {
        'set-cookie': [
          'session=abc; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/',
          'token=xyz; Path=/',
        ],
        'accept': ['text/html', 'application/xhtml+xml'],
      };
      final normalized = normalizeHeaders(headers);
      expect(
        normalized['set-cookie'],
        'session=abc; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/\ntoken=xyz; Path=/',
      );
      expect(normalized['accept'], 'text/html, application/xhtml+xml');
    });

    test('normalizeHeaders is case-insensitive for Set-Cookie', () {
      final headers = {
        'Set-Cookie': [
          'session=abc; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/',
          'token=xyz; Path=/',
        ],
      };
      final normalized = normalizeHeaders(headers);
      expect(
        normalized['Set-Cookie'],
        'session=abc; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/\ntoken=xyz; Path=/',
      );
    });

    test('mapHeaderEntries converts map to list of key-value maps', () {
      final headers = {'x-api-key': 'secret', 'accept': '*/*'};
      final harFormat = mapHeaderEntries(
        headers,
        keyName: 'name',
        valueName: 'value',
      );
      expect(
          harFormat,
          equals([
            {'name': 'x-api-key', 'value': 'secret'},
            {'name': 'accept', 'value': '*/*'},
          ]));

      final postmanFormat = mapHeaderEntries(
        headers,
        keyName: 'key',
        valueName: 'value',
      );
      expect(
          postmanFormat,
          equals([
            {'key': 'x-api-key', 'value': 'secret'},
            {'key': 'accept', 'value': '*/*'},
          ]));
    });
  });
}

class _ThrowingObject {
  @override
  String toString() => throw StateError('boom');
}
