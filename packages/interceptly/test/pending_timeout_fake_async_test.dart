// ignore_for_file: invalid_use_of_internal_member

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/engine/memory_index.dart';
import 'package:interceptly/src/engine/pending_tracker.dart';
import 'package:interceptly/src/model/index_entry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('Pending Request Timeout with fakeAsync', () {
    test('recordPending with fakeAsync advancing 45s marks entry as timeout',
        () {
      fakeAsync((async) {
        final engine = InterceptlyEngine(
          settings: const InterceptlySettings(
            pendingTimeout: Duration(seconds: 45),
          ),
        );
        addTearDown(engine.dispose);

        engine.recordPending(
          id: 'pending-1',
          method: 'GET',
          url: 'https://api.example.com/slow',
          timestamp: DateTime.now(),
        );

        expect(engine.entries.length, equals(1));
        var entry = engine.entries.first;
        expect(entry.id, equals('pending-1'));
        expect(entry.statusCode, equals(0));
        expect(entry.hasError, isFalse);
        expect(entry.errorType, isNull);

        async.elapse(const Duration(seconds: 30));
        entry = engine.entries.first;
        expect(entry.hasError, isFalse);
        expect(entry.errorType, isNull);

        async.elapse(const Duration(seconds: 15));
        entry = engine.entries.first;
        expect(entry.hasError, isTrue);
        expect(entry.errorType, equals('TimeoutException'));
        expect(entry.statusCode, equals(0));
        expect((entry as IndexEntry).domain, equals('api.example.com'));
      });
    });

    test('closeRealtimeConnection before 45s cancels pending timeout timer',
        () {
      fakeAsync((async) {
        final engine = InterceptlyEngine(
          settings: const InterceptlySettings(
            pendingTimeout: Duration(seconds: 45),
          ),
        );
        addTearDown(engine.dispose);

        engine.recordPending(
          id: 'ws-conn-1',
          method: 'WS',
          url: 'wss://echo.websocket.events',
          timestamp: DateTime.now(),
        );

        expect(engine.entries.first.hasError, isFalse);

        async.elapse(const Duration(seconds: 20));
        engine.closeRealtimeConnection('ws-conn-1', closeCode: 1000);

        async.elapse(const Duration(seconds: 30));

        final entry = engine.entries.first;
        expect(entry.statusCode, equals(1000));
        expect(entry.hasError, isFalse);
        expect(entry.errorType, isNull);
        expect((entry as IndexEntry).domain, equals('echo.websocket.events'));
      });
    });

    test('custom pendingTimeout is respected when configured', () {
      fakeAsync((async) {
        final engine = InterceptlyEngine(
          settings: const InterceptlySettings(
            pendingTimeout: Duration(seconds: 10),
          ),
        );
        addTearDown(engine.dispose);

        engine.recordPending(
          id: 'custom-timeout',
          method: 'GET',
          url: 'https://api.example.com/quick-timeout',
          timestamp: DateTime.now(),
        );

        async.elapse(const Duration(seconds: 9));
        expect(engine.entries.first.hasError, isFalse);

        async.elapse(const Duration(seconds: 2));
        final entry = engine.entries.first;
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
        final engine = InterceptlyEngine(
          settings: const InterceptlySettings(
            pendingTimeout: Duration(seconds: 45),
          ),
        );
        addTearDown(engine.dispose);

        engine.recordPending(
          id: 'req-a',
          method: 'GET',
          url: 'https://api.example.com/a',
          timestamp: DateTime.now(),
        );

        async.elapse(const Duration(seconds: 15));

        engine.recordPending(
          id: 'req-b',
          method: 'GET',
          url: 'https://api.example.com/b',
          timestamp: DateTime.now(),
        );

        async.elapse(const Duration(seconds: 30));

        final entryA = engine.entries.firstWhere((e) => e.id == 'req-a');
        final entryB = engine.entries.firstWhere((e) => e.id == 'req-b');

        expect(entryA.hasError, isTrue);
        expect(entryA.errorType, equals('TimeoutException'));
        expect(entryB.hasError, isFalse);

        async.elapse(const Duration(seconds: 15));
        final entryBAfter = engine.entries.firstWhere((e) => e.id == 'req-b');
        expect(entryBAfter.hasError, isTrue);
        expect(entryBAfter.errorType, equals('TimeoutException'));
      });
    });

    test('recordRealtimeConnection does NOT time out after pendingTimeout', () {
      fakeAsync((async) {
        final engine = InterceptlyEngine(
          settings: const InterceptlySettings(
            pendingTimeout: Duration(seconds: 45),
          ),
        );
        addTearDown(engine.dispose);

        engine.recordRealtimeConnection(
          id: 'ws-persistent',
          url: 'wss://api.example.com/live',
          timestamp: DateTime.now(),
        );

        expect(engine.entries.length, equals(1));
        var entry = engine.entries.first;
        expect(entry.id, equals('ws-persistent'));
        expect(entry.isRealtime, isTrue);
        expect(entry.statusCode, equals(0));
        expect(entry.hasError, isFalse);

        async.elapse(const Duration(seconds: 100));

        entry = engine.entries.first;
        expect(entry.statusCode, equals(0));
        expect(entry.hasError, isFalse);
        expect(entry.errorType, isNull);
      });
    });
  });
}
