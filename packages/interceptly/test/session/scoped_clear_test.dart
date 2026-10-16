import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';

/// Scoped clear: the AppBar delete button clears only the active tab.
void main() {
  group('InspectorSession scoped clear', () {
    late InspectorSession session;

    setUp(() {
      session = InspectorSession();
      session.recordPending(
        id: 'req_1',
        method: 'GET',
        url: 'https://api.example.com/items',
        timestamp: DateTime(2026, 10, 14, 10, 0, 0),
      );
      session.recordRealtimeConnection(
        id: 'ws_1',
        url: 'wss://socket.example.com/feed',
        timestamp: DateTime(2026, 10, 14, 10, 1, 0),
      );
    });

    tearDown(() async {
      await session.dispose();
    });

    test('clearRest removes REST entries and keeps realtime', () async {
      await session.clearRest();

      final ids = session.entries.map((e) => e.id).toList();
      expect(ids, contains('ws_1'));
      expect(ids, isNot(contains('req_1')));
    });

    test('clearRealtime removes realtime entries and keeps REST', () async {
      await session.clearRealtime();

      final ids = session.entries.map((e) => e.id).toList();
      expect(ids, contains('req_1'));
      expect(ids, isNot(contains('ws_1')));
    });

    test('clearRealtime drops realtime frames, clearRest keeps them',
        () async {
      await session.recordRealtimeFrame(
        RealtimeFrame(
          id: 'f_1',
          sessionId: 'ws_1',
          direction: FrameDirection.incoming,
          type: FrameType.text,
          textPayload: 'hello',
        ),
      );
      expect(session.getRealtimeFrames('ws_1'), hasLength(1));

      await session.clearRest();
      expect(session.getRealtimeFrames('ws_1'), hasLength(1));

      await session.recordRealtimeFrame(
        RealtimeFrame(
          id: 'f_2',
          sessionId: 'ws_1',
          direction: FrameDirection.incoming,
          type: FrameType.text,
          textPayload: 'again',
        ),
      );
      await session.clearRealtime();
      expect(session.getRealtimeFrames('ws_1'), isEmpty);
    });

    test('scoped clear resets the REST filter like clear() does', () async {
      session.applyFilter(
        RequestFilter(methods: {'POST'}),
      );
      expect(session.filter.isEmpty, isFalse);

      await session.clearRest();
      expect(session.filter.isEmpty, isTrue);
    });

    test('sequential clears keep working after new records arrive', () async {
      await session.clearRest();
      expect(session.entries.map((e) => e.id), contains('ws_1'));

      session.recordPending(
        id: 'req_2',
        method: 'POST',
        url: 'https://api.example.com/items',
        timestamp: DateTime(2026, 10, 14, 10, 2, 0),
      );
      await session.clearRealtime();
      expect(
        session.entries.map((e) => e.id).toList(),
        contains('req_2'),
      );
      expect(
        session.entries.map((e) => e.id),
        isNot(contains('ws_1')),
      );

      await session.clear();
      expect(session.entries, isEmpty);
    });
  });
}
