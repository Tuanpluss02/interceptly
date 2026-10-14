import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/adapter.dart';

void main() {
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
      // 'é' is 2 bytes: 0xC3 0xA9
      expect(truncateUtf8('hé', 2), equals('h'));
      expect(truncateUtf8('hé', 3), equals('hé'));

      // 'Việt Nam'
      // 'V' (1), 'i' (1), 'ệ' (3 bytes: 0xE1 0xBB 0x87), 't' (1)
      expect(truncateUtf8('Việt', 2), equals('Vi'));
      expect(truncateUtf8('Việt', 3), equals('Vi'));
      expect(truncateUtf8('Việt', 4), equals('Vi'));
      expect(truncateUtf8('Việt', 5), equals('Việ'));
      expect(truncateUtf8('Việt', 6), equals('Việt'));

      // Emoji 4 bytes: 😀
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
          builder.toBytesOrNull(), equals(Uint8List.fromList([1, 2, 3, 4, 5])));
    });

    test(
        'teeStreamCapture forwards chunks and calls onDone with captured bytes',
        () async {
      final source = Stream.fromIterable([
        [1, 2],
        [3, 4],
      ]);

      Uint8List? captured;
      final teed = teeStreamCapture(
        source,
        maxBytes: 10,
        onDone: (bytes) => captured = bytes,
        onError: (_, __, ___) {},
        onCancel: (_) {},
      );

      final forwarded = await teed.toList();
      expect(
          forwarded,
          equals([
            [1, 2],
            [3, 4]
          ]));
      expect(captured, equals(Uint8List.fromList([1, 2, 3, 4])));
    });

    test('teeStreamCapture handles error properly', () async {
      final controller = StreamController<List<int>>();
      Object? receivedError;
      Uint8List? captured;

      final teed = teeStreamCapture(
        controller.stream,
        maxBytes: 10,
        onDone: (_) {},
        onError: (err, st, bytes) {
          receivedError = err;
          captured = bytes;
        },
        onCancel: (_) {},
      );

      final sub = teed.listen((_) {}, onError: (_) {});
      controller.add([1, 2]);
      controller.addError(Exception('stream-broken'));

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(receivedError, isA<Exception>());
      expect(captured, equals(Uint8List.fromList([1, 2])));
      await sub.cancel();
      await controller.close();
    });

    test('teeStreamCapture handles cancellation', () async {
      final controller = StreamController<List<int>>();
      bool canceled = false;
      Uint8List? captured;

      final teed = teeStreamCapture(
        controller.stream,
        maxBytes: 10,
        onDone: (_) {},
        onError: (_, __, ___) {},
        onCancel: (bytes) {
          canceled = true;
          captured = bytes;
        },
      );

      final sub = teed.listen((_) {});
      controller.add([1, 2, 3]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await sub.cancel();

      expect(canceled, isTrue);
      expect(captured, equals(Uint8List.fromList([1, 2, 3])));
      await controller.close();
    });
  });
}
