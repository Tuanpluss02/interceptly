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

      // Subsequent call hits cache
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
  });
}
