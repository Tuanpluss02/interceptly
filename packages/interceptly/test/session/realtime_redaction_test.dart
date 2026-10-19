// ignore_for_file: invalid_use_of_internal_member
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/adapter/realtime_traffic_collector.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';
import 'package:interceptly/src/model/realtime_frame.dart';

void main() {
  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('Realtime traffic collection', () {
    test('realtime connection records headers and query params intact',
        () async {
      final session = InterceptlyEngine.instance;
      session.recordRealtimeConnection(
        id: 'ws1',
        url: 'wss://x/?token=SECRET',
        headers: {'Authorization': 'Bearer S'},
      );
      final entry = session.byId('ws1');
      expect(entry?.requestHeaders['Authorization'], 'Bearer S');
      expect(entry?.url, contains('SECRET'));
    });

    test('shouldCapture false suppresses realtime connection', () async {
      final session = InterceptlyEngine.instance;
      session.configure(
        const InterceptlySettings(shouldCapture: _blockAll),
      );
      session
          .recordRealtimeConnection(id: 'ws-no', url: 'wss://x/', headers: {});
      expect(session.byId('ws-no'), isNull);
    });

    test('realtime frames preserve raw text and binary payloads', () async {
      final session = InterceptlyEngine.instance;
      final collector = DefaultRealtimeTrafficCollector();
      collector.recordFrame(
        sessionId: 'ws-raw',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        payload: '{"secret":"12345"}',
      );
      collector.recordFrame(
        sessionId: 'ws-raw',
        direction: FrameDirection.outgoing,
        type: FrameType.binary,
        payload: Uint8List.fromList([1, 2, 3]),
      );
      final frames = session.getRealtimeFrames('ws-raw');
      expect(frames, hasLength(2));
      expect(frames[0].textPayload, '{"secret":"12345"}');
      expect(frames[1].binaryPayload, equals(Uint8List.fromList([1, 2, 3])));
    });

    test('frames for filtered sessions are skipped', () async {
      final session = InterceptlyEngine.instance;
      session.configure(InterceptlySettings(
        shouldCapture: (url) => !url.contains('blocked'),
      ));
      session.recordRealtimeConnection(
          id: 'ws-blocked', url: 'wss://x/blocked', headers: {});
      expect(session.byId('ws-blocked'), isNull);
      DefaultRealtimeTrafficCollector().recordFrame(
        sessionId: 'ws-blocked',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        payload: 'should not be stored',
      );
      expect(session.getRealtimeFrames('ws-blocked'), isEmpty);
      session.recordRealtimeConnection(
          id: 'ws-ok', url: 'wss://x/allowed', headers: {});
      expect(session.byId('ws-ok'), isNotNull);
      DefaultRealtimeTrafficCollector().recordFrame(
        sessionId: 'ws-ok',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        payload: 'kept',
      );
      expect(session.getRealtimeFrames('ws-ok'), hasLength(1));
    });
  });
}

bool _blockAll(String _) => false;
