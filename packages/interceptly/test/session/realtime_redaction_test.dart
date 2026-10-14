import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';

void main() {
  group('Realtime redaction (Task 3)', () {
    test('realtime connection redacts headers and query params', () async {
      final session = InspectorSession(settings: InterceptlySettings(
        redactedHeaders: {'authorization'},
        redactedQueryParams: {'token'},
      ));
      addTearDown(session.dispose);
      session.recordRealtimeConnection(id: 'ws1', url: 'wss://x/?token=SECRET', headers: {'Authorization': 'Bearer S'});
      final entry = session.byId('ws1');
      expect(entry?.requestHeaders['Authorization'], '[REDACTED]');
      expect(entry?.url, isNot(contains('SECRET')));
    });

    test('realtime frame applies bodyRedactor to text payload', () async {
      final session = InspectorSession(settings: InterceptlySettings(
        bodyRedactor: (b) => null,
      ));
      addTearDown(session.dispose);
      DefaultRealtimeTrafficCollector(session).recordFrame(
        sessionId: 'ws1', direction: FrameDirection.incoming, type: FrameType.text, payload: '{"password":"x"}');
      expect(session.getRealtimeFrames('ws1'), isNotEmpty);
    });

    test('shouldCapture false suppresses realtime connection', () async {
      final session = InspectorSession(settings: InterceptlySettings(shouldCapture: (_) => false));
      addTearDown(session.dispose);
      session.recordRealtimeConnection(id: 'ws-no', url: 'wss://x/', headers: {});
      expect(session.byId('ws-no'), isNull);
    });

    test('text frame body is transformed by bodyRedactor', () async {
      final session = InspectorSession(settings: InterceptlySettings(
        bodyRedactor: (Uint8List? body) {
          if (body == null) return null;
          final text = utf8.decode(body);
          final redacted = text.replaceAll('SECRET', '[REDACTED]');
          return Uint8List.fromList(utf8.encode(redacted));
        },
      ));
      addTearDown(session.dispose);
      DefaultRealtimeTrafficCollector(session).recordFrame(
        sessionId: 'ws-text',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        payload: '{"token":"SECRET"}',
      );
      final frames = session.getRealtimeFrames('ws-text');
      expect(frames, hasLength(1));
      expect(frames.first.textPayload, isNot(contains('SECRET')));
      expect(frames.first.textPayload, contains('[REDACTED]'));
    });

    test('text frame falls back to original when bodyRedactor throws', () async {
      final session = InspectorSession(settings: InterceptlySettings(
        bodyRedactor: (Uint8List? body) => throw StateError('redactor boom'),
      ));
      addTearDown(session.dispose);
      DefaultRealtimeTrafficCollector(session).recordFrame(
        sessionId: 'ws-throw',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        payload: 'original-payload',
      );
      final frames = session.getRealtimeFrames('ws-throw');
      expect(frames, hasLength(1));
      expect(frames.first.textPayload, 'original-payload');
    });

    test('text frame tolerates non-UTF8 redactor output', () async {
      final session = InspectorSession(settings: InterceptlySettings(
        bodyRedactor: (Uint8List? body) => Uint8List.fromList([0xFF, 0xFE, 0x41]),
      ));
      addTearDown(session.dispose);
      DefaultRealtimeTrafficCollector(session).recordFrame(
        sessionId: 'ws-malformed',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        payload: 'hello',
      );
      final frames = session.getRealtimeFrames('ws-malformed');
      expect(frames, hasLength(1));
      expect(frames.first.textPayload, isNotNull);
    });

    test('binary frame bytes pass through bodyRedactor', () async {
      final session = InspectorSession(settings: InterceptlySettings(
        bodyRedactor: (Uint8List? body) => Uint8List.fromList([9, 9, 9]),
      ));
      addTearDown(session.dispose);
      DefaultRealtimeTrafficCollector(session).recordFrame(
        sessionId: 'ws-bin',
        direction: FrameDirection.outgoing,
        type: FrameType.binary,
        payload: Uint8List.fromList([1, 2, 3]),
      );
      final frames = session.getRealtimeFrames('ws-bin');
      expect(frames, hasLength(1));
      expect(frames.first.binaryPayload, equals(Uint8List.fromList([9, 9, 9])));
    });

    test('frames for filtered sessions are skipped', () async {
      final session = InspectorSession(settings: InterceptlySettings(
        shouldCapture: (url) => !url.contains('blocked'),
      ));
      addTearDown(session.dispose);
      session.recordRealtimeConnection(id: 'ws-blocked', url: 'wss://x/blocked', headers: {});
      expect(session.byId('ws-blocked'), isNull);
      DefaultRealtimeTrafficCollector(session).recordFrame(
        sessionId: 'ws-blocked',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        payload: 'should not be stored',
      );
      expect(session.getRealtimeFrames('ws-blocked'), isEmpty);
      session.recordRealtimeConnection(id: 'ws-ok', url: 'wss://x/allowed', headers: {});
      expect(session.byId('ws-ok'), isNotNull);
      DefaultRealtimeTrafficCollector(session).recordFrame(
        sessionId: 'ws-ok',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        payload: 'kept',
      );
      expect(session.getRealtimeFrames('ws-ok'), hasLength(1));
    });

    test('updateSettings mid-stream picks up new redactor', () async {
      final session = InspectorSession(settings: const InterceptlySettings());
      addTearDown(session.dispose);
      final collector = DefaultRealtimeTrafficCollector(session);
      collector.recordFrame(
        sessionId: 'ws-mid',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        payload: 'SECRET-one',
      );
      expect(session.getRealtimeFrames('ws-mid').first.textPayload, contains('SECRET-one'));
      session.configureSession(InterceptlySettings(
        bodyRedactor: (Uint8List? body) {
          if (body == null) return null;
          return Uint8List.fromList(utf8.encode(utf8.decode(body).replaceAll('SECRET', '[REDACTED]')));
        },
      ));
      collector.recordFrame(
        sessionId: 'ws-mid',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        payload: 'SECRET-two',
      );
      final frames = session.getRealtimeFrames('ws-mid');
      expect(frames, hasLength(2));
      expect(frames[1].textPayload, isNot(contains('SECRET-two')));
    });
  });
}
