import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';
import 'package:interceptly/src/session/inspector_session.dart';
import 'package:interceptly/src/session/memory_index.dart';
import 'package:interceptly/src/session/pending_tracker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pending Request Timeout with fakeAsync', () {
    test('recordPending with fakeAsync advancing 45s marks entry as timeout', () {
      fakeAsync((async) {
        final session = InspectorSession(
          settings: const InterceptlySettings(
            pendingTimeout: Duration(seconds: 45),
          ),
        );
        addTearDown(session.dispose);

        session.recordPending(
          id: 'pending-1',
          method: 'GET',
          url: 'https://api.example.com/slow',
          timestamp: DateTime.now(),
        );

        expect(session.entries.length, equals(1));
        var entry = session.entries.first;
        expect(entry.id, equals('pending-1'));
        expect(entry.statusCode, equals(0));
        expect(entry.hasError, isFalse);
        expect(entry.errorType, isNull);

        // Advance 30 seconds - should still be pending without error
        async.elapse(const Duration(seconds: 30));
        entry = session.entries.first;
        expect(entry.hasError, isFalse);
        expect(entry.errorType, isNull);

        // Advance another 15 seconds (total 45s) - should mark as timeout
        async.elapse(const Duration(seconds: 15));
        entry = session.entries.first;
        expect(entry.hasError, isTrue);
        expect(entry.errorType, equals('TimeoutException'));
        expect(entry.statusCode, equals(0));
        expect((entry as IndexEntry).domain, equals('api.example.com'));
      });
    });

    test('closeRealtimeConnection before 45s cancels pending timeout timer', () {
      fakeAsync((async) {
        final session = InspectorSession(
          settings: const InterceptlySettings(
            pendingTimeout: Duration(seconds: 45),
          ),
        );
        addTearDown(session.dispose);

        session.recordPending(
          id: 'ws-conn-1',
          method: 'WS',
          url: 'wss://echo.websocket.events',
          timestamp: DateTime.now(),
        );

        expect(session.entries.first.hasError, isFalse);

        // Advance 20 seconds, then close connection normally
        async.elapse(const Duration(seconds: 20));
        session.closeRealtimeConnection('ws-conn-1', closeCode: 1000);

        // Advance past 45 seconds
        async.elapse(const Duration(seconds: 30));

        final entry = session.entries.first;
        expect(entry.statusCode, equals(1000));
        expect(entry.hasError, isFalse);
        expect(entry.errorType, isNull);
        expect((entry as IndexEntry).domain, equals('echo.websocket.events'));
      });
    });

    test('custom pendingTimeout is respected when configured', () {
      fakeAsync((async) {
        final session = InspectorSession(
          settings: const InterceptlySettings(
            pendingTimeout: Duration(seconds: 10),
          ),
        );
        addTearDown(session.dispose);

        session.recordPending(
          id: 'custom-timeout',
          method: 'GET',
          url: 'https://api.example.com/quick-timeout',
          timestamp: DateTime.now(),
        );

        async.elapse(const Duration(seconds: 9));
        expect(session.entries.first.hasError, isFalse);

        async.elapse(const Duration(seconds: 2));
        final entry = session.entries.first;
        expect(entry.hasError, isTrue);
        expect(entry.errorType, equals('TimeoutException'));
      });
    });

    test('cancelling pending request prevents TimeoutException firing', () {
      fakeAsync((async) {
        final index = MemoryIndex(maxEntries: 10);
        IndexEntry? timedOut;

        final tracker = PendingTracker(
          timeoutDuration: const Duration(seconds: 45),
          memoryIndex: index,
          onTimeout: (e) => timedOut = e,
        );

        tracker.recordPending(
          id: 'manual-cancel',
          method: 'GET',
          url: 'https://api.example.com/item',
          timestamp: DateTime.now(),
          settings: const InterceptlySettings(),
        );

        expect(index.entries.first.hasError, isFalse);

        async.elapse(const Duration(seconds: 20));
        tracker.cancel('manual-cancel');

        async.elapse(const Duration(seconds: 30));
        expect(timedOut, isNull);
        expect(index.entries.first.hasError, isFalse);
      });
    });

    test('multiple concurrent pending requests timeout independently', () {
      fakeAsync((async) {
        final session = InspectorSession(
          settings: const InterceptlySettings(
            pendingTimeout: Duration(seconds: 45),
          ),
        );
        addTearDown(session.dispose);

        session.recordPending(
          id: 'req-a',
          method: 'GET',
          url: 'https://api.example.com/a',
          timestamp: DateTime.now(),
        );

        async.elapse(const Duration(seconds: 15));

        session.recordPending(
          id: 'req-b',
          method: 'GET',
          url: 'https://api.example.com/b',
          timestamp: DateTime.now(),
        );

        // At t = 45s from start (elapsed 30s more): req-a has lived 45s, req-b has lived 30s
        async.elapse(const Duration(seconds: 30));

        final entryA = session.entries.firstWhere((e) => e.id == 'req-a');
        final entryB = session.entries.firstWhere((e) => e.id == 'req-b');

        expect(entryA.hasError, isTrue);
        expect(entryA.errorType, equals('TimeoutException'));
        expect(entryB.hasError, isFalse);

        // At t = 60s (elapsed 15s more): req-b reaches 45s and times out
        async.elapse(const Duration(seconds: 15));
        final entryBAfter = session.entries.firstWhere((e) => e.id == 'req-b');
        expect(entryBAfter.hasError, isTrue);
        expect(entryBAfter.errorType, equals('TimeoutException'));
      });
    });

    test('recordRealtimeConnection does NOT time out after pendingTimeout', () {
      fakeAsync((async) {
        final session = InspectorSession(
          settings: const InterceptlySettings(
            pendingTimeout: Duration(seconds: 45),
          ),
        );
        addTearDown(session.dispose);

        session.recordRealtimeConnection(
          id: 'ws-persistent',
          url: 'wss://api.example.com/live',
          timestamp: DateTime.now(),
        );

        expect(session.entries.length, equals(1));
        var entry = session.entries.first;
        expect(entry.id, equals('ws-persistent'));
        expect(entry.isRealtime, isTrue);
        expect(entry.statusCode, equals(0));
        expect(entry.hasError, isFalse);

        // Advance 100 seconds (well past 45s pending timeout)
        async.elapse(const Duration(seconds: 100));

        entry = session.entries.first;
        expect(entry.statusCode, equals(0));
        expect(entry.hasError, isFalse);
        expect(entry.errorType, isNull);
      });
    });
  });
}
