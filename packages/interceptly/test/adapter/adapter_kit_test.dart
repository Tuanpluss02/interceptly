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
            [3, 4]
          ]));
      expect(captured, equals(Uint8List.fromList([1, 2, 3, 4])));
      expect(capturedTotal, equals(4));
    });

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
    });

    test('CappedBytesBuilder retains unbounded bytes when maxBytes <= 0', () {
      final builder = CappedBytesBuilder(0);
      builder.add([1, 2, 3]);
      builder.add([4, 5, 6, 7]);

      expect(builder.isTruncated, isFalse);
      expect(builder.totalBytes, equals(7));
      expect(builder.toBytesOrNull(),
          equals(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7])));
    });

    test(
        'bindResponseStream passes captured capped bytes and original totalBytes to complete',
        () async {
      int? reportedStatus;
      Uint8List? reportedBytes;
      int? reportedTotalSize;

      final spy = _SpyHttpCollector(
        onComplete: ({
          required context,
          required statusCode,
          headers,
          bodyBytes,
          responseSizeBytes,
          durationMs,
          responseContentType,
        }) {
          reportedStatus = statusCode;
          reportedBytes = bodyBytes;
          reportedTotalSize = responseSizeBytes;
        },
      );

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

      // maxBodyBytes is 4, but stream length is 10
      final bound = scope.bindResponseStream(stream, statusCode: 200);
      await bound.drain<void>();

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(reportedStatus, equals(200));
      expect(reportedBytes, equals(Uint8List.fromList([1, 2, 3, 4])));
      expect(reportedTotalSize, equals(10));
    });
  });
}

class _SpyHttpCollector implements HttpTrafficCollector {
  _SpyHttpCollector({this.onComplete});

  final void Function({
    required HttpRequestContext context,
    required int statusCode,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    int? responseSizeBytes,
    int? durationMs,
    String? responseContentType,
  })? onComplete;

  @override
  int get maxBodyBytes => 4;

  @override
  Duration delayForChunk(int chunkBytes) => Duration.zero;

  @override
  bool shouldCapture(Uri? uri) => true;

  @override
  Future<HttpCaptureScope> begin({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    String? contentType,
    String? requestId,
  }) async =>
      HttpCaptureScope.inactive(this);

  @override
  Future<HttpRequestContext?> startRequest({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    String? contentType,
    String? requestId,
  }) async =>
      null;

  @override
  Future<void> completeResponse({
    required HttpRequestContext context,
    required int statusCode,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    int? responseSizeBytes,
    int? durationMs,
    String? responseContentType,
    bool? responseTruncatedAtStorage,
  }) async {
    onComplete?.call(
      context: context,
      statusCode: statusCode,
      headers: headers,
      bodyBytes: bodyBytes,
      responseSizeBytes: responseSizeBytes,
      durationMs: durationMs,
      responseContentType: responseContentType,
    );
  }

  @override
  void failRequest({
    required HttpRequestContext context,
    required Object error,
    String? errorType,
    String? errorMessage,
    int? statusCode,
    Map<String, String>? responseHeaders,
    Uint8List? responseBodyBytes,
    int? responseSizeBytes,
    int? durationMs,
    bool? responseTruncatedAtStorage,
  }) {}
}
