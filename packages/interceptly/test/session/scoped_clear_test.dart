// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';

/// Scoped clear: clears only the active tab traffic.
void main() {
  group('InterceptlyEngine scoped clear', () {
    late InterceptlyEngine engine;

    setUp(() async {
      await Interceptly.resetForTesting();
      engine = InterceptlyEngine();
      engine.recordPending(
        id: 'req_1',
        method: 'GET',
        url: 'https://api.example.com/items',
        timestamp: DateTime(2026, 10, 14, 10, 0, 0),
      );
      engine.recordRealtimeConnection(
        id: 'ws_1',
        url: 'wss://socket.example.com/feed',
        timestamp: DateTime(2026, 10, 14, 10, 1, 0),
      );
    });

    tearDown(() async {
      await engine.dispose();
      await Interceptly.resetForTesting();
    });

    test('clearRest removes REST entries and keeps realtime', () async {
      await engine.clearRest();

      final ids = engine.entries.map((e) => e.id).toList();
      expect(ids, contains('ws_1'));
      expect(ids, isNot(contains('req_1')));
    });

    test('clearRealtime removes realtime entries and keeps REST', () async {
      await engine.clearRealtime();

      final ids = engine.entries.map((e) => e.id).toList();
      expect(ids, contains('req_1'));
      expect(ids, isNot(contains('ws_1')));
    });

    test('clearRealtime drops realtime frames, clearRest keeps them', () async {
      await engine.recordRealtimeFrame(
        RealtimeFrame(
          id: 'f_1',
          sessionId: 'ws_1',
          direction: FrameDirection.incoming,
          type: FrameType.text,
          textPayload: 'hello',
        ),
      );
      expect(engine.getRealtimeFrames('ws_1'), hasLength(1));

      await engine.clearRest();
      expect(engine.getRealtimeFrames('ws_1'), hasLength(1));

      await engine.recordRealtimeFrame(
        RealtimeFrame(
          id: 'f_2',
          sessionId: 'ws_1',
          direction: FrameDirection.incoming,
          type: FrameType.text,
          textPayload: 'again',
        ),
      );
      await engine.clearRealtime();
      expect(engine.getRealtimeFrames('ws_1'), isEmpty);
    });

    test('sequential clears keep working after new records arrive', () async {
      await engine.clearRest();
      expect(engine.entries.map((e) => e.id), contains('ws_1'));

      engine.recordPending(
        id: 'req_2',
        method: 'POST',
        url: 'https://api.example.com/items',
        timestamp: DateTime(2026, 10, 14, 10, 2, 0),
      );
      await engine.clearRealtime();
      expect(
        engine.entries.map((e) => e.id).toList(),
        contains('req_2'),
      );
      expect(
        engine.entries.map((e) => e.id),
        isNot(contains('ws_1')),
      );

      await engine.clear();
      expect(engine.entries, isEmpty);
    });
  });
}
