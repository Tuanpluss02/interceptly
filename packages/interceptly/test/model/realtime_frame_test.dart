import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';

void main() {
  group('RealtimeFrame', () {
    final fixedTime = DateTime(2026, 10, 13, 12, 0, 0);

    test('direct constructor initializes all fields', () {
      final frame = RealtimeFrame(
        id: 'frame-1',
        sessionId: 'session-1',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        textPayload: 'Hello Interceptly',
        payloadSizeBytes: 17,
        timestamp: fixedTime,
      );

      expect(frame.id, 'frame-1');
      expect(frame.sessionId, 'session-1');
      expect(frame.direction, FrameDirection.incoming);
      expect(frame.type, FrameType.text);
      expect(frame.textPayload, 'Hello Interceptly');
      expect(frame.binaryPayload, isNull);
      expect(frame.payloadSizeBytes, 17);
      expect(frame.timestamp, fixedTime);
      expect(frame.isText, isTrue);
      expect(frame.isBinary, isFalse);
      expect(frame.isIncoming, isTrue);
      expect(frame.isOutgoing, isFalse);
    });

    test('direct constructor computes payloadSizeBytes from text when omitted', () {
      const text = 'Hello UTF-8: Xin chào 🚀';
      final expectedBytes = utf8.encode(text).length;

      final frame = RealtimeFrame(
        id: 'frame-text-auto',
        sessionId: 'session-1',
        direction: FrameDirection.outgoing,
        type: FrameType.text,
        textPayload: text,
        timestamp: fixedTime,
      );

      expect(frame.payloadSizeBytes, expectedBytes);
      expect(frame.isOutgoing, isTrue);
      expect(frame.isIncoming, isFalse);
    });

    test('direct constructor computes payloadSizeBytes from binary when omitted', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final frame = RealtimeFrame(
        id: 'frame-bin-auto',
        sessionId: 'session-1',
        direction: FrameDirection.incoming,
        type: FrameType.binary,
        binaryPayload: bytes,
        timestamp: fixedTime,
      );

      expect(frame.payloadSizeBytes, 8);
      expect(frame.binaryPayload, bytes);
      expect(frame.isBinary, isTrue);
      expect(frame.isText, isFalse);
    });

    test('RealtimeFrame.text factory constructor', () {
      const text = 'WebSocket Test Frame';
      final frame = RealtimeFrame.text(
        id: 'frame-2',
        sessionId: 'ws-sess',
        direction: FrameDirection.outgoing,
        text: text,
        timestamp: fixedTime,
      );

      expect(frame.id, 'frame-2');
      expect(frame.sessionId, 'ws-sess');
      expect(frame.direction, FrameDirection.outgoing);
      expect(frame.type, FrameType.text);
      expect(frame.textPayload, text);
      expect(frame.binaryPayload, isNull);
      expect(frame.payloadSizeBytes, utf8.encode(text).length);
      expect(frame.timestamp, fixedTime);
      expect(frame.isText, isTrue);
      expect(frame.isBinary, isFalse);
      expect(frame.isOutgoing, isTrue);
      expect(frame.isIncoming, isFalse);
    });

    test('RealtimeFrame.text factory supports explicit payloadSizeBytes override', () {
      final frame = RealtimeFrame.text(
        id: 'frame-override',
        sessionId: 'ws-sess',
        direction: FrameDirection.incoming,
        text: 'trimmed',
        payloadSizeBytes: 100,
        timestamp: fixedTime,
      );

      expect(frame.payloadSizeBytes, 100);
      expect(frame.textPayload, 'trimmed');
    });

    test('RealtimeFrame.binary factory constructor', () {
      final data = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final frame = RealtimeFrame.binary(
        id: 'frame-3',
        sessionId: 'ws-sess',
        direction: FrameDirection.incoming,
        bytes: data,
        timestamp: fixedTime,
      );

      expect(frame.id, 'frame-3');
      expect(frame.sessionId, 'ws-sess');
      expect(frame.direction, FrameDirection.incoming);
      expect(frame.type, FrameType.binary);
      expect(frame.textPayload, isNull);
      expect(frame.binaryPayload, data);
      expect(frame.payloadSizeBytes, 4);
      expect(frame.timestamp, fixedTime);
      expect(frame.isText, isFalse);
      expect(frame.isBinary, isTrue);
      expect(frame.isIncoming, isTrue);
      expect(frame.isOutgoing, isFalse);
    });

    test('RealtimeFrame.binary factory supports explicit payloadSizeBytes override', () {
      final data = Uint8List.fromList([1, 2, 3]);
      final frame = RealtimeFrame.binary(
        id: 'frame-bin-override',
        sessionId: 'ws-sess',
        direction: FrameDirection.outgoing,
        bytes: data,
        payloadSizeBytes: 50,
      );

      expect(frame.payloadSizeBytes, 50);
      expect(frame.binaryPayload, data);
    });

    test('FrameType covers ping, pong, close, ack', () {
      final ping = RealtimeFrame(
        id: 'ping-1',
        sessionId: 'sess',
        direction: FrameDirection.outgoing,
        type: FrameType.ping,
      );
      final pong = RealtimeFrame(
        id: 'pong-1',
        sessionId: 'sess',
        direction: FrameDirection.incoming,
        type: FrameType.pong,
      );
      final close = RealtimeFrame(
        id: 'close-1',
        sessionId: 'sess',
        direction: FrameDirection.outgoing,
        type: FrameType.close,
      );
      final ack = RealtimeFrame(
        id: 'ack-1',
        sessionId: 'sess',
        direction: FrameDirection.incoming,
        type: FrameType.ack,
      );

      expect(ping.type, FrameType.ping);
      expect(pong.type, FrameType.pong);
      expect(close.type, FrameType.close);
      expect(ack.type, FrameType.ack);
      expect(ping.isText, isFalse);
      expect(ping.isBinary, isFalse);
    });

    test('supports eventName for event-driven protocols like Socket.IO', () {
      final frame = RealtimeFrame(
        id: 'f-event',
        sessionId: 'sess-1',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        textPayload: '{"msg":"hi"}',
        eventName: 'chat:message',
      );

      expect(frame.eventName, equals('chat:message'));

      final textFrame = RealtimeFrame.text(
        id: 'f-text-event',
        sessionId: 'sess-1',
        direction: FrameDirection.outgoing,
        text: 'hello',
        eventName: 'join:room',
      );
      expect(textFrame.eventName, equals('join:room'));

      final copied = frame.copyWith(eventName: 'chat:updated');
      expect(copied.eventName, equals('chat:updated'));

      final frameNoEvent = RealtimeFrame(
        id: 'f-no-event',
        sessionId: 'sess-1',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        textPayload: '{"msg":"hi"}',
      );
      expect(frameNoEvent.eventName, isNull);
      expect(frame, isNot(equals(frameNoEvent)));
    });

    test('operator == and hashCode include binaryPayload equality', () {
      final bytesA = Uint8List.fromList([1, 2, 3]);
      final bytesB = Uint8List.fromList([1, 2, 3]);

      final frame1 = RealtimeFrame.binary(
        id: 'f-bin-eq',
        sessionId: 's-eq',
        direction: FrameDirection.incoming,
        bytes: bytesA,
        timestamp: fixedTime,
      );

      final frame2 = RealtimeFrame.binary(
        id: 'f-bin-eq',
        sessionId: 's-eq',
        direction: FrameDirection.incoming,
        bytes: bytesA,
        timestamp: fixedTime,
      );

      final frame3 = RealtimeFrame.binary(
        id: 'f-bin-eq',
        sessionId: 's-eq',
        direction: FrameDirection.incoming,
        bytes: bytesB,
        timestamp: fixedTime,
      );

      expect(frame1 == frame2, isTrue);
      expect(frame1.hashCode, equals(frame2.hashCode));

      // Distinct Uint8List instances are not identical
      expect(frame1 == frame3, isFalse);
    });
  });

  group('InterceptlySettings maxFramesPerSession', () {
    test('default value is 1000', () {
      const settings = InterceptlySettings();
      expect(settings.maxFramesPerSession, 1000);
    });

    test('custom value via constructor', () {
      const settings = InterceptlySettings(maxFramesPerSession: 250);
      expect(settings.maxFramesPerSession, 250);
    });

    test('copyWith updates maxFramesPerSession', () {
      const settings = InterceptlySettings();
      final updated = settings.copyWith(maxFramesPerSession: 500);
      expect(updated.maxFramesPerSession, 500);
      expect(updated.maxEntries, settings.maxEntries);
      expect(updated.bodyOffloadThreshold, settings.bodyOffloadThreshold);
    });

    test('copyWith preserves maxFramesPerSession when null', () {
      const settings = InterceptlySettings(maxFramesPerSession: 750);
      final updated = settings.copyWith(maxEntries: 100);
      expect(updated.maxFramesPerSession, 750);
      expect(updated.maxEntries, 100);
    });
  });
}
