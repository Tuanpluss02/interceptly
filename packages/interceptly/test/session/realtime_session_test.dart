import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';

void main() {
  group('InspectorSession Realtime Frame Recording', () {
    test('stores frames accessible via getRealtimeFrames', () {
      final session = InspectorSession();
      addTearDown(session.dispose);

      final frame1 = RealtimeFrame.text(
        id: 'f-1',
        sessionId: 'ws-100',
        direction: FrameDirection.incoming,
        text: '{"event":"connected"}',
      );
      final frame2 = RealtimeFrame.text(
        id: 'f-2',
        sessionId: 'ws-100',
        direction: FrameDirection.outgoing,
        text: '{"action":"subscribe"}',
      );

      session.recordRealtimeFrame(frame1);
      session.recordRealtimeFrame(frame2);

      final frames = session.getRealtimeFrames('ws-100');
      expect(frames.length, equals(2));
      expect(frames[0].id, equals('f-1'));
      expect(frames[0].textPayload, equals('{"event":"connected"}'));
      expect(frames[1].id, equals('f-2'));
      expect(frames[1].textPayload, equals('{"action":"subscribe"}'));

      // getFrames alias should return the exact same frames
      expect(session.getFrames('ws-100'), equals(frames));

      // Unknown session returns empty list
      expect(session.getRealtimeFrames('ws-unknown'), isEmpty);
    });

    test('isolates frames across distinct sessions', () {
      final session = InspectorSession();
      addTearDown(session.dispose);

      session.recordRealtimeFrame(
        RealtimeFrame.text(
          id: 'f-a1',
          sessionId: 'session-a',
          direction: FrameDirection.incoming,
          text: 'a1',
        ),
      );
      session.recordRealtimeFrame(
        RealtimeFrame.text(
          id: 'f-b1',
          sessionId: 'session-b',
          direction: FrameDirection.outgoing,
          text: 'b1',
        ),
      );

      expect(session.getRealtimeFrames('session-a').length, equals(1));
      expect(session.getRealtimeFrames('session-a').first.id, equals('f-a1'));
      expect(session.getRealtimeFrames('session-b').length, equals(1));
      expect(session.getRealtimeFrames('session-b').first.id, equals('f-b1'));
    });

    test('ignores frames when session is disabled and resumes on enable', () {
      final session = InspectorSession();
      addTearDown(session.dispose);

      session.disable();
      expect(session.isEnabled, isFalse);

      session.recordRealtimeFrame(
        RealtimeFrame.text(
          id: 'f-dropped',
          sessionId: 'ws-drop',
          direction: FrameDirection.incoming,
          text: 'should be dropped',
        ),
      );

      expect(session.getRealtimeFrames('ws-drop'), isEmpty);

      session.enable();
      expect(session.isEnabled, isTrue);

      session.recordRealtimeFrame(
        RealtimeFrame.text(
          id: 'f-kept',
          sessionId: 'ws-drop',
          direction: FrameDirection.incoming,
          text: 'should be kept',
        ),
      );

      expect(session.getRealtimeFrames('ws-drop').length, equals(1));
      expect(session.getRealtimeFrames('ws-drop').first.id, equals('f-kept'));
    });
  });

  group('Ring buffer capacity & eviction', () {
    test('drops oldest frames and retains newest when exceeding maxFramesPerSession', () {
      final session = InspectorSession(
        settings: const InterceptlySettings(maxFramesPerSession: 3),
      );
      addTearDown(session.dispose);

      for (var i = 1; i <= 5; i++) {
        session.recordRealtimeFrame(
          RealtimeFrame.text(
            id: 'frame-$i',
            sessionId: 'ws-bounded',
            direction: FrameDirection.incoming,
            text: 'payload-$i',
          ),
        );
      }

      final frames = session.getRealtimeFrames('ws-bounded');
      expect(frames.length, equals(3));
      expect(frames.map((f) => f.id).toList(), equals(['frame-3', 'frame-4', 'frame-5']));
      expect(frames.first.id, equals('frame-3'));
      expect(frames.last.id, equals('frame-5'));
    });

    test('retains newest frames when maxFramesPerSession shrinks via configureSession', () {
      final session = InspectorSession(
        settings: const InterceptlySettings(maxFramesPerSession: 5),
      );
      addTearDown(session.dispose);

      for (var i = 1; i <= 5; i++) {
        session.recordRealtimeFrame(
          RealtimeFrame.text(
            id: 'frame-$i',
            sessionId: 'ws-shrink',
            direction: FrameDirection.incoming,
            text: 'payload-$i',
          ),
        );
      }
      expect(session.getRealtimeFrames('ws-shrink').length, equals(5));

      session.configureSession(
        const InterceptlySettings(maxFramesPerSession: 2),
      );

      final shrunk = session.getRealtimeFrames('ws-shrink');
      expect(shrunk.length, equals(2));
      expect(shrunk.map((f) => f.id).toList(), equals(['frame-4', 'frame-5']));
    });
  });

  group('Message Storm Ticking Throttler', () {
    test('burst of 500 frames within 50ms batches notifyListeners within ~100ms', () {
      fakeAsync((async) {
        final session = InspectorSession(
          settings: const InterceptlySettings(maxFramesPerSession: 100),
        );
        addTearDown(session.dispose);

        var notifyCount = 0;
        session.addListener(() => notifyCount++);

        // Burst of 500 frames simulated across 50ms
        for (var i = 0; i < 500; i++) {
          session.recordRealtimeFrame(
            RealtimeFrame.text(
              id: 'storm-$i',
              sessionId: 'ws-storm',
              direction: i.isEven ? FrameDirection.incoming : FrameDirection.outgoing,
              text: 'storm message $i',
            ),
          );
          if (i % 10 == 0) {
            async.elapse(const Duration(milliseconds: 1));
          }
        }

        // Within the 50ms window, zero notifications should have fired yet
        expect(notifyCount, equals(0));

        // Advance to 99ms total: throttler has not fired yet
        async.elapse(const Duration(milliseconds: 49));
        expect(notifyCount, equals(0));

        // Advance past 100ms throttle interval
        async.elapse(const Duration(milliseconds: 15));
        expect(notifyCount, equals(1));

        // No new frames arrive -> remaining idle without extra notifications
        async.elapse(const Duration(milliseconds: 200));
        expect(notifyCount, equals(1));

        // Verify ring buffer capped at 100
        final retainedFrames = session.getRealtimeFrames('ws-storm');
        expect(retainedFrames.length, equals(100));
        expect(retainedFrames.first.id, equals('storm-400'));
        expect(retainedFrames.last.id, equals('storm-499'));

        // Next burst of frames triggers a new throttled notification cycle
        session.recordRealtimeFrame(
          RealtimeFrame.text(
            id: 'burst2-1',
            sessionId: 'ws-storm',
            direction: FrameDirection.incoming,
            text: 'after idle',
          ),
        );

        // Before 100ms
        async.elapse(const Duration(milliseconds: 50));
        expect(notifyCount, equals(1));

        // After 100ms window
        async.elapse(const Duration(milliseconds: 60));
        expect(notifyCount, equals(2));
      });
    });
  });

  group('InspectorSession Lifecycle: clear and dispose', () {
    test('clear wipes stored realtime frames and cancels throttler timer', () {
      fakeAsync((async) {
        final session = InspectorSession();
        addTearDown(session.dispose);

        session.recordRealtimeFrame(
          RealtimeFrame.text(
            id: 'f-clear',
            sessionId: 'ws-clear',
            direction: FrameDirection.incoming,
            text: 'to be cleared',
          ),
        );
        expect(session.getRealtimeFrames('ws-clear').length, equals(1));

        var notifyCount = 0;
        session.addListener(() => notifyCount++);

        // Call clear before the 100ms throttler timer fires
        session.clear();
        expect(session.getRealtimeFrames('ws-clear'), isEmpty);
        expect(notifyCount, equals(1)); // clear() itself calls notifyListeners()

        // Advance past throttle window - canceled timer must not fire again
        async.elapse(const Duration(milliseconds: 200));
        expect(notifyCount, equals(1));
      });
    });

    test('dispose cancels throttler timer cleanly and releases frames', () {
      fakeAsync((async) {
        final session = InspectorSession();

        session.recordRealtimeFrame(
          RealtimeFrame.text(
            id: 'f-dispose',
            sessionId: 'ws-dispose',
            direction: FrameDirection.incoming,
            text: 'to be disposed',
          ),
        );
        expect(session.getRealtimeFrames('ws-dispose').length, equals(1));

        session.dispose();
        expect(session.getRealtimeFrames('ws-dispose'), isEmpty);

        // Advancing time must not throw FlutterError on disposed ChangeNotifier
        expect(
          () => async.elapse(const Duration(milliseconds: 200)),
          returnsNormally,
        );
      });
    });
  });

  group('Interceptly Facade Forwarders', () {
    test('recordRealtimeFrame and getRealtimeFrames forward to session', () {
      final session = InspectorSession();
      addTearDown(session.dispose);

      final interceptly = Interceptly(session: session);
      addTearDown(interceptly.dispose);

      final frame = RealtimeFrame.text(
        id: 'f-facade',
        sessionId: 'ws-facade',
        direction: FrameDirection.incoming,
        text: 'hello via facade',
      );

      interceptly.recordRealtimeFrame(frame);

      expect(interceptly.getRealtimeFrames('ws-facade').length, equals(1));
      expect(interceptly.getRealtimeFrames('ws-facade').first.id, equals('f-facade'));
      expect(interceptly.getFrames('ws-facade'), equals(interceptly.getRealtimeFrames('ws-facade')));
      expect(session.getRealtimeFrames('ws-facade').length, equals(1));
    });

    test('recordRealtimeConnection and closeRealtimeConnection update session entries', () {
      final session = InspectorSession();
      addTearDown(session.dispose);

      final interceptly = Interceptly(session: session);
      addTearDown(interceptly.dispose);

      interceptly.recordRealtimeConnection(
        id: 'conn-1',
        url: 'wss://echo.example.com/ws',
        headers: {'sec-websocket-protocol': 'chat'},
      );

      expect(interceptly.calls.length, equals(1));
      expect(interceptly.calls.first.id, equals('conn-1'));
      expect(interceptly.calls.first.method, equals('WS'));
      expect(interceptly.calls.first.url, equals('wss://echo.example.com/ws'));
      expect(interceptly.calls.first.statusCode, equals(0));

      interceptly.closeRealtimeConnection('conn-1', closeCode: 1000);

      expect(interceptly.calls.first.statusCode, equals(1000));
      expect(interceptly.calls.first.hasError, isFalse);
    });
  });
}
