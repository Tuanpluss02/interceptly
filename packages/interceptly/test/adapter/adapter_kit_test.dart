import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/adapter.dart';

import '../helpers/spy_traffic_collectors.dart';

void main() {
  group('normalizeHeaders', () {
    test('converts simple string values to string map', () {
      final input = <String, Object?>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer token123',
      };
      final result = normalizeHeaders(input);
      expect(
        result,
        equals({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer token123',
        }),
      );
    });

    test('joins multi-value list headers with comma delimiter', () {
      final input = <String, Object?>{
        'Accept': ['application/json', 'text/plain'],
        'Cache-Control': ['no-cache', 'no-store'],
      };
      final result = normalizeHeaders(input);
      expect(
        result,
        equals({
          'Accept': 'application/json, text/plain',
          'Cache-Control': 'no-cache, no-store',
        }),
      );
    });

    test('joins Set-Cookie multi-values with newline delimiter', () {
      final input = <String, Object?>{
        'Set-Cookie': ['sessionId=abc; Path=/', 'token=xyz; Secure'],
        'set-cookie': ['a=1', 'b=2'],
      };
      final result = normalizeHeaders(input);
      expect(
        result['Set-Cookie'],
        equals('sessionId=abc; Path=/\ntoken=xyz; Secure'),
      );
      expect(result['set-cookie'], equals('a=1\nb=2'));
    });

    test('handles non-string and null values gracefully', () {
      final input = <String, Object?>{
        'content-length': 1024,
        'x-enabled': true,
        'x-null': null,
      };
      final result = normalizeHeaders(input);
      expect(result['content-length'], equals('1024'));
      expect(result['x-enabled'], equals('true'));
      expect(result['x-null'], equals(''));
    });
  });

  group('mapHeaderEntries', () {
    test('maps header entries using default key/value field names', () {
      final headers = {
        'content-type': 'application/json',
        'authorization': 'Bearer token',
      };
      final entries = mapHeaderEntries(headers);
      expect(
        entries,
        equals([
          {'name': 'content-type', 'value': 'application/json'},
          {'name': 'authorization', 'value': 'Bearer token'},
        ]),
      );
    });

    test('maps header entries using custom field names', () {
      final headers = {'x-key': 'x-val'};
      final entries =
          mapHeaderEntries(headers, keyName: 'header', valueName: 'val');
      expect(
        entries,
        equals([
          {'header': 'x-key', 'val': 'x-val'},
        ]),
      );
    });
  });

  group('encodeBodyBytes', () {
    test('returns null when body is null', () {
      expect(encodeBodyBytes(null), isNull);
    });

    test('returns exact Uint8List when body is already Uint8List', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      expect(encodeBodyBytes(bytes), equals(bytes));
    });

    test('converts List<int> to Uint8List', () {
      final list = <int>[10, 20, 30];
      final result = encodeBodyBytes(list);
      expect(result, isA<Uint8List>());
      expect(result, equals(Uint8List.fromList(list)));
    });

    test('encodes String via UTF-8', () {
      const text = 'hello world';
      expect(
        encodeBodyBytes(text),
        equals(Uint8List.fromList(utf8.encode(text))),
      );
    });

    test('encodes Map and List to JSON UTF-8 bytes', () {
      final map = {'hello': 'world'};
      expect(
        encodeBodyBytes(map),
        equals(Uint8List.fromList(utf8.encode('{"hello":"world"}'))),
      );

      final list = [1, 'two', 3];
      expect(
        encodeBodyBytes(list),
        equals(Uint8List.fromList(utf8.encode('[1,"two",3]'))),
      );
    });

    test('formats placeholder byte representation for Stream', () {
      final stream = Stream<List<int>>.fromIterable([
        [1, 2]
      ]);
      expect(
        encodeBodyBytes(stream),
        equals(Uint8List.fromList(utf8.encode('[streamed body]'))),
      );
    });

    test('falls back gracefully to toString() on custom objects', () {
      final obj = DateTime(2026, 1, 1);
      expect(
        encodeBodyBytes(obj),
        equals(Uint8List.fromList(utf8.encode(obj.toString()))),
      );
    });
  });

  group('truncateUtf8', () {
    test('returns original string when within maxBytes or unconstrained', () {
      expect(truncateUtf8('hello world', 0), equals('hello world'));
      expect(truncateUtf8('hello world', -1), equals('hello world'));
      expect(truncateUtf8('hello', 10), equals('hello'));
      expect(truncateUtf8('hello', 5), equals('hello'));
    });

    test('truncates ASCII correctly', () {
      expect(truncateUtf8('hello world', 5), equals('hello'));
    });

    test('does not break multi-byte UTF-8 sequences', () {
      expect(truncateUtf8('hé', 2), equals('h'));
      expect(truncateUtf8('hé', 3), equals('hé'));

      expect(truncateUtf8('Việt', 2), equals('Vi'));
      expect(truncateUtf8('Việt', 3), equals('Vi'));
      expect(truncateUtf8('Việt', 4), equals('Vi'));
      expect(truncateUtf8('Việt', 5), equals('Việ'));
      expect(truncateUtf8('Việt', 6), equals('Việt'));

      expect(truncateUtf8('a😀b', 3), equals('a'));
      expect(truncateUtf8('a😀b', 5), equals('a😀'));
    });
  });

  group('summarizeMultipart', () {
    test('formats fields and files into standardized summary', () {
      final summaryBytes = summarizeMultipart(
        fields: [
          const MapEntry('username', 'alice'),
          const MapEntry('type', 'admin'),
        ],
        files: [
          const MultipartFileInfo(
            field: 'avatar',
            filename: 'photo.jpg',
            contentType: 'image/jpeg',
            length: 1024,
          ),
          const MultipartFileInfo(
            field: 'doc',
          ),
        ],
      );

      final text = utf8.decode(summaryBytes);
      expect(
        text,
        equals(
          '[field] username=alice\n'
          '[field] type=admin\n'
          '[file] avatar: photo.jpg (image/jpeg, 1024 bytes)\n'
          '[file] doc: blob (application/octet-stream)',
        ),
      );
    });
  });

  group('CappedBytesBuilder & teeStreamCapture', () {
    test('CappedBytesBuilder caps byte capacity', () {
      final builder = CappedBytesBuilder(5);
      builder.add([1, 2, 3]);
      expect(builder.totalBytes, equals(3));
      expect(builder.isTruncated, isFalse);

      builder.add([4, 5, 6, 7]);
      expect(builder.totalBytes, equals(7));
      expect(builder.isTruncated, isTrue);
      expect(
        builder.toBytesOrNull(),
        equals(Uint8List.fromList([1, 2, 3, 4, 5])),
      );
    });

    test(
      'teeStreamCapture forwards chunks and calls onDone with captured bytes',
      () async {
        final source = Stream.fromIterable([
          [1, 2],
          [3, 4],
        ]);

        Uint8List? captured;
        int? capturedTotal;
        final teed = teeStreamCapture(
          source,
          maxBytes: 10,
          onDone: (bytes, total) {
            captured = bytes;
            capturedTotal = total;
          },
          onError: (_, __, ___, ____) {},
          onCancel: (_, __) {},
        );

        final forwarded = await teed.toList();
        expect(
          forwarded,
          equals([
            [1, 2],
            [3, 4],
          ]),
        );
        expect(captured, equals(Uint8List.fromList([1, 2, 3, 4])));
        expect(capturedTotal, equals(4));
      },
    );

    test('teeStreamCapture handles error properly', () async {
      final controller = StreamController<List<int>>();
      Object? receivedError;
      Uint8List? captured;
      int? capturedTotal;

      final teed = teeStreamCapture(
        controller.stream,
        maxBytes: 10,
        onDone: (_, __) {},
        onError: (err, st, bytes, total) {
          receivedError = err;
          captured = bytes;
          capturedTotal = total;
        },
        onCancel: (_, __) {},
      );

      final sub = teed.listen((_) {}, onError: (_) {});
      controller.add([1, 2]);
      controller.addError(Exception('stream-broken'));

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(receivedError, isA<Exception>());
      expect(captured, equals(Uint8List.fromList([1, 2])));
      expect(capturedTotal, equals(2));
      await sub.cancel();
      await controller.close();
    });

    test('teeStreamCapture handles cancellation', () async {
      final controller = StreamController<List<int>>();
      bool canceled = false;
      Uint8List? captured;
      int? capturedTotal;

      final teed = teeStreamCapture(
        controller.stream,
        maxBytes: 10,
        onDone: (_, __) {},
        onError: (_, __, ___, ____) {},
        onCancel: (bytes, total) {
          canceled = true;
          captured = bytes;
          capturedTotal = total;
        },
      );

      final sub = teed.listen((_) {});
      controller.add([1, 2, 3]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await sub.cancel();

      expect(canceled, isTrue);
      expect(captured, equals(Uint8List.fromList([1, 2, 3])));
      expect(capturedTotal, equals(3));
      await controller.close();
    });

    test(
      'teeStreamCapture preserves FIFO chunk delivery and onDone ordering under delay',
      () async {
        final source = Stream.fromIterable([
          [1, 2],
          [3, 4],
          [5, 6],
        ]);

        Uint8List? captured;
        int? capturedTotal;
        final teed = teeStreamCapture(
          source,
          maxBytes: 10,
          chunkDelay: (bytes) => const Duration(milliseconds: 10),
          onDone: (bytes, total) {
            captured = bytes;
            capturedTotal = total;
          },
          onError: (_, __, ___, ____) {},
          onCancel: (_, __) {},
        );

        final forwarded = await teed.toList();
        expect(
          forwarded,
          equals([
            [1, 2],
            [3, 4],
            [5, 6],
          ]),
        );
        expect(captured, equals(Uint8List.fromList([1, 2, 3, 4, 5, 6])));
        expect(capturedTotal, equals(6));
      },
    );

    test('CappedBytesBuilder retains unbounded bytes when maxBytes <= 0', () {
      final builder = CappedBytesBuilder(0);
      builder.add([1, 2, 3]);
      builder.add([4, 5, 6, 7]);

      expect(builder.isTruncated, isFalse);
      expect(builder.totalBytes, equals(7));
      expect(
        builder.toBytesOrNull(),
        equals(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7])),
      );
    });

    test(
      'bindResponseStream passes captured capped bytes and original totalBytes to complete',
      () async {
        final spy = SpyHttpTrafficCollector(maxBodyBytes: 4);

        final scope = HttpCaptureScope(
          collector: spy,
          context: HttpRequestContext(
            id: 'test-1',
            method: 'GET',
            uri: Uri.parse('https://example.com/large'),
            startedAt: DateTime.now(),
          ),
        );

        final stream = Stream.fromIterable([
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9, 10],
        ]);

        final bound = scope.bindResponseStream(stream, statusCode: 200);
        await bound.drain<void>();

        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(spy.completeResponseCalls.length, equals(1));
        final call = spy.completeResponseCalls.first;
        expect(call['statusCode'], equals(200));
        expect(call['bodyBytes'], equals(Uint8List.fromList([1, 2, 3, 4])));
        expect(call['responseSizeBytes'], equals(10));
        expect(call['responseTruncatedAtStorage'], isTrue);
      },
    );
  });
}
