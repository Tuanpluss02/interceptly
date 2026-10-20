import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/realtime_frame.dart';
import 'package:interceptly/src/ui/detail/realtime/realtime_formatters.dart';

void main() {
  group('RealtimeFormatters', () {
    test('formatFrameTimestamp formats DateTime with millisecond padding', () {
      final dt = DateTime(2026, 10, 14, 9, 5, 3, 42);
      expect(formatFrameTimestamp(dt), '09:05:03.042');
    });

    test('frameTypeLabel returns capitalized readable names for all FrameTypes',
        () {
      expect(frameTypeLabel(FrameType.text), 'Text');
      expect(frameTypeLabel(FrameType.binary), 'Binary');
      expect(frameTypeLabel(FrameType.ping), 'Ping');
      expect(frameTypeLabel(FrameType.pong), 'Pong');
      expect(frameTypeLabel(FrameType.close), 'Close');
      expect(frameTypeLabel(FrameType.ack), 'Ack');
    });

    test('formatBinaryPreview formats empty, short, and long byte buffers', () {
      expect(formatBinaryPreview(Uint8List(0)), '[empty binary]');

      final shortBytes = Uint8List.fromList([0x01, 0x0A, 0xFF]);
      expect(formatBinaryPreview(shortBytes), '[binary: 3 bytes] 01 0a ff');

      final longBytes = Uint8List.fromList(List.generate(20, (i) => i));
      final preview = formatBinaryPreview(longBytes);
      expect(preview.startsWith('[binary: 20 bytes] 00 01 02'), isTrue);
      expect(preview.endsWith('...'), isTrue);
    });

    test(
        'getFramePayloadString returns text, binary preview, or uppercase fallback',
        () {
      final textFrame = RealtimeFrame.text(
        id: 'f1',
        sessionId: 's1',
        direction: FrameDirection.incoming,
        text: 'hello world',
      );
      expect(getFramePayloadString(textFrame), 'hello world');

      final binFrame = RealtimeFrame.binary(
        id: 'f2',
        sessionId: 's1',
        direction: FrameDirection.outgoing,
        bytes: Uint8List.fromList([1, 2]),
      );
      expect(getFramePayloadString(binFrame), '[binary: 2 bytes] 01 02');

      final pingFrame = RealtimeFrame(
        id: 'f3',
        sessionId: 's1',
        direction: FrameDirection.incoming,
        type: FrameType.ping,
        timestamp: DateTime.now(),
      );
      expect(getFramePayloadString(pingFrame), 'PING');

      final offloadedFrame = RealtimeFrame.offloaded(
        id: 'f4',
        sessionId: 's1',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        payloadSizeBytes: 5000,
        shortPreview: '{"offloaded":"preview"}',
        fileOffset: 0,
        fileLength: 5000,
        rotationCount: 0,
      );
      expect(getFramePayloadString(offloadedFrame), '{"offloaded":"preview"}');
    });

    test('tryParseJsonPayload parses valid JSON and populates cache', () {
      final cache = <String, dynamic>{};
      final frame = RealtimeFrame.text(
        id: 'f4',
        sessionId: 's1',
        direction: FrameDirection.incoming,
        text: '{"status":"ok","code":200}',
      );

      final result = tryParseJsonPayload(frame, cache);
      expect(result, isA<Map<String, dynamic>>());
      expect(result['status'], 'ok');
      expect(cache['f4'], equals(result));

      expect(tryParseJsonPayload(frame, cache), equals(result));
    });

    test('tryParseJsonPayload caches null on non-json text or null payload',
        () {
      final cache = <String, dynamic>{};
      final frame = RealtimeFrame.text(
        id: 'f5',
        sessionId: 's1',
        direction: FrameDirection.incoming,
        text: 'plain non json',
      );

      expect(tryParseJsonPayload(frame, cache), isNull);
      expect(cache.containsKey('f5'), isTrue);
      expect(cache['f5'], isNull);
    });

    group('tryDecodeBinaryToText', () {
      test('returns null for empty bytes', () {
        expect(tryDecodeBinaryToText(Uint8List(0)), isNull);
      });

      test('decodes valid ASCII text', () {
        final bytes = Uint8List.fromList('Hello Interceptly!'.codeUnits);
        expect(tryDecodeBinaryToText(bytes), 'Hello Interceptly!');
      });

      test('decodes valid UTF-8 text with Vietnamese and emojis', () {
        final text = 'Xin chào thế giới! 🚀 Socket message';
        final bytes = Uint8List.fromList(utf8.encode(text));
        expect(tryDecodeBinaryToText(bytes), text);
      });

      test('allows tabs, newlines, and carriage returns', () {
        final text = '{\n\t"key": "value"\r\n}';
        final bytes = Uint8List.fromList(utf8.encode(text));
        expect(tryDecodeBinaryToText(bytes), text);
      });

      test('returns null for invalid UTF-8 bytes', () {
        final invalidBytes = Uint8List.fromList([0xFF, 0xFE, 0xFD]);
        expect(tryDecodeBinaryToText(invalidBytes), isNull);
      });

      test('returns null for binary data with null byte or control characters',
          () {
        final nullByteData = Uint8List.fromList([0x48, 0x65, 0x00, 0x6C, 0x6F]);
        expect(tryDecodeBinaryToText(nullByteData), isNull);

        final controlData = Uint8List.fromList([0x48, 0x07, 0x6C]);
        expect(tryDecodeBinaryToText(controlData), isNull);
      });
    });

    test(
        'getFramePayloadString returns decoded text when binary contains valid text',
        () {
      final binFrame = RealtimeFrame.binary(
        id: 'f_bin_text',
        sessionId: 's1',
        direction: FrameDirection.incoming,
        bytes: Uint8List.fromList('WebSocket UTF-8 message'.codeUnits),
      );
      expect(getFramePayloadString(binFrame), 'WebSocket UTF-8 message');
    });

    test('tryParseJsonPayload parses valid JSON from binary frame', () {
      final cache = <String, dynamic>{};
      final jsonBytes = Uint8List.fromList(
        utf8.encode('{"type":"ping","count":42}'),
      );
      final binFrame = RealtimeFrame.binary(
        id: 'f_bin_json',
        sessionId: 's1',
        direction: FrameDirection.incoming,
        bytes: jsonBytes,
      );

      final result = tryParseJsonPayload(binFrame, cache);
      expect(result, isA<Map<String, dynamic>>());
      expect(result['type'], 'ping');
      expect(result['count'], 42);
      expect(cache['f_bin_json'], equals(result));
    });
  });
}
