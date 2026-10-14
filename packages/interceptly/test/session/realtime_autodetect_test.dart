import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/adapter/realtime_traffic_collector.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';
import 'package:interceptly/src/session/inspector_session.dart';

void main() {
  group('Realtime Capability Auto-Detection', () {
    late InspectorSession session;

    setUp(() {
      session = InspectorSession();
    });

    tearDown(() {
      session.dispose();
    });

    test('isRealtimeActive is false by default when no realtime events occurred', () {
      expect(session.isRealtimeActive, isFalse);
    });

    test('isRealtimeActive is true when settings explicitly enable realtime', () {
      session.configureSession(const InterceptlySettings(enableRealtime: true));
      expect(session.isRealtimeActive, isTrue);
    });

    test('isRealtimeActive is true after recordRealtimeConnection is invoked', () {
      expect(session.isRealtimeActive, isFalse);

      session.recordRealtimeConnection(
        id: 'ws_1',
        url: 'wss://echo.websocket.events',
      );

      expect(session.isRealtimeActive, isTrue);
    });

    test('markRealtimeActive sets isRealtimeActive to true and notifies listeners', () {
      var notified = 0;
      session.addListener(() => notified++);

      session.markRealtimeActive();

      expect(session.isRealtimeActive, isTrue);
      expect(notified, equals(1));

      // Idempotent: second call does not notify unnecessarily
      session.markRealtimeActive();
      expect(notified, equals(1));
    });

    test('DefaultRealtimeTrafficCollector triggers markRealtimeActive on openSession and recordConnection', () {
      final collector = DefaultRealtimeTrafficCollector(session: session);
      expect(session.isRealtimeActive, isFalse);

      collector.openSession(uri: Uri.parse('wss://example.com/socket'));
      expect(session.isRealtimeActive, isTrue);
    });

    test('RealtimeTrafficCollector.markActive activates realtime capability', () {
      RealtimeTrafficCollector.instance = DefaultRealtimeTrafficCollector(session: session);
      expect(session.isRealtimeActive, isFalse);

      RealtimeTrafficCollector.markActive();
      expect(session.isRealtimeActive, isTrue);
    });

    test('session.clear does not revert isRealtimeActive once activated', () {
      session.markRealtimeActive();
      expect(session.isRealtimeActive, isTrue);

      session.clear();
      expect(session.isRealtimeActive, isTrue);
    });

    test('isRealtimeActive detects other realtime protocols like SIO or SSE in entries', () {
      expect(session.isRealtimeActive, isFalse);
      session.recordPending(
        id: 'sio_1',
        method: 'SIO',
        url: 'https://example.com/socket.io',
        timestamp: DateTime.now(),
      );
      expect(session.isRealtimeActive, isTrue);
    });
  });
}
