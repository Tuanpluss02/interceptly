import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';

void main() {
  group('Realtime Message Storm & Throughput Stress Tests', () {
    test(
      'Test 1: 10 concurrent sessions x 1,000 frames (10,000 frames total) - bounds & FIFO eviction',
      () async {
        const capacity = 500;
        final session = InspectorSession(
          settings: const InterceptlySettings(maxFramesPerSession: capacity),
        );
        addTearDown(session.dispose);

        const sessionCount = 10;
        const framesPerSession = 1000;

        // Concurrently bombard 10 independent sessions with 1,000 frames each
        // (10,000 frames total)
        await Future.wait(
          List.generate(sessionCount, (sIndex) async {
            final sessionId = 'storm-session-$sIndex';
            for (var fIndex = 0; fIndex < framesPerSession; fIndex++) {
              session.recordRealtimeFrame(
                RealtimeFrame.text(
                  id: 'frame-$sIndex-$fIndex',
                  sessionId: sessionId,
                  direction: fIndex.isEven
                      ? FrameDirection.incoming
                      : FrameDirection.outgoing,
                  text: 'session $sIndex payload $fIndex',
                ),
              );

              // Yield periodically to allow interleaved asynchronous scheduling
              if (fIndex % 100 == 0) {
                await Future<void>.delayed(Duration.zero);
              }
            }
          }),
        );

        // Verify bounds and FIFO preservation across all 10 sessions
        for (var sIndex = 0; sIndex < sessionCount; sIndex++) {
          final sessionId = 'storm-session-$sIndex';
          final frames = session.getRealtimeFrames(sessionId);

          // 1. Buffer bound: never exceeds maxFramesPerSession (500)
          expect(
            frames.length,
            equals(capacity),
            reason: 'Session $sessionId must contain exactly $capacity frames',
          );

          // 2. FIFO eviction: earliest frames (0..499) dropped, latest preserved (500..999)
          final expectedStartSeq = framesPerSession - capacity; // 500
          expect(
            frames.first.id,
            equals('frame-$sIndex-$expectedStartSeq'),
            reason:
                'Earliest preserved frame must be sequence $expectedStartSeq',
          );
          expect(
            frames.last.id,
            equals('frame-$sIndex-${framesPerSession - 1}'),
            reason: 'Latest frame must be preserved',
          );

          // 3. Strict sequential integrity of preserved frames
          for (var i = 0; i < frames.length; i++) {
            final expectedSeq = expectedStartSeq + i;
            expect(frames[i].id, equals('frame-$sIndex-$expectedSeq'));
            expect(
              frames[i].textPayload,
              equals('session $sIndex payload $expectedSeq'),
            );
          }
        }
      },
    );

    test(
      'Test 1.1: Default settings (1,000 capacity) with 10 sessions x 1,200 frames (12,000 frames total)',
      () async {
        final session = InspectorSession(
          settings: const InterceptlySettings(
            maxFramesPerSession: 1000,
            maxTotalRealtimeFrames: 10000,
          ),
        );
        addTearDown(session.dispose);

        const sessionCount = 10;
        const framesPerSession = 1200;

        await Future.wait(
          List.generate(sessionCount, (sIndex) async {
            final sessionId = 'default-sess-$sIndex';
            for (var fIndex = 0; fIndex < framesPerSession; fIndex++) {
              session.recordRealtimeFrame(
                RealtimeFrame.text(
                  id: 'def-$sIndex-$fIndex',
                  sessionId: sessionId,
                  direction: FrameDirection.incoming,
                  text: 'msg-$fIndex',
                ),
              );
            }
          }),
        );

        for (var sIndex = 0; sIndex < sessionCount; sIndex++) {
          final sessionId = 'default-sess-$sIndex';
          final frames = session.getRealtimeFrames(sessionId);

          expect(frames.length, equals(1000));
          expect(frames.first.id, equals('def-$sIndex-200'));
          expect(frames.last.id, equals('def-$sIndex-1199'));
        }
      },
    );

    test(
      'Test 2: Ticking Throttler Message Storm Protection with fakeAsync',
      () {
        fakeAsync((async) {
          final session = InspectorSession(
            settings: const InterceptlySettings(maxFramesPerSession: 1000),
          );
          addTearDown(session.dispose);

          var notifyCount = 0;
          session.addListener(() => notifyCount++);

          // 1. Rapid burst of 1,000 frames arriving within 50ms
          for (var i = 0; i < 1000; i++) {
            session.recordRealtimeFrame(
              RealtimeFrame.text(
                id: 'burst-$i',
                sessionId: 'ws-storm',
                direction: i.isEven
                    ? FrameDirection.incoming
                    : FrameDirection.outgoing,
                text: 'burst payload $i',
              ),
            );
            if (i % 20 == 0) {
              async.elapse(const Duration(milliseconds: 1));
            }
          }

          // At elapsed 50ms, the 100ms throttle timer has not fired yet
          expect(
            notifyCount,
            equals(0),
            reason: 'Zero notifications during active frame storm burst',
          );

          // Advance to 99ms total: timer still pending
          async.elapse(const Duration(milliseconds: 49));
          expect(notifyCount, equals(0));

          // Cross the 100ms throttle boundary
          async.elapse(const Duration(milliseconds: 15));
          expect(
            notifyCount,
            equals(1),
            reason:
                'Burst of 1,000 frames must trigger exactly 1 batched notification',
          );

          // 2. High-frequency sustained stream over 500ms
          // 250 frames spaced every 2ms
          for (var i = 0; i < 250; i++) {
            session.recordRealtimeFrame(
              RealtimeFrame.text(
                id: 'sustained-$i',
                sessionId: 'ws-storm',
                direction: FrameDirection.incoming,
                text: 'sustained payload $i',
              ),
            );
            async.elapse(const Duration(milliseconds: 2));
          }

          // With ~100ms throttling over 500ms, notifications are batched
          // to ~5 callbacks rather than 250 individual UI thrashings
          expect(
            notifyCount,
            inInclusiveRange(4, 7),
            reason:
                'Sustained storm must batch notifications at ~100ms intervals',
          );

          // 3. Idle period: no spurious notifications after storm ceases
          final countAfterStorm = notifyCount;
          async.elapse(const Duration(milliseconds: 500));
          expect(
            notifyCount,
            equals(countAfterStorm),
            reason: 'No additional notifications when no frames are recorded',
          );
        });
      },
    );

    test(
      'Test 3: Concurrent dispose & clear under flight without exceptions',
      () async {
        final session = InspectorSession(
          settings: const InterceptlySettings(maxFramesPerSession: 500),
        );

        var recording = true;
        var totalRecorded = 0;

        // Background worker tasks continuously bombarding session
        final workers = Future.wait(
          List.generate(5, (workerId) async {
            var seq = 0;
            while (recording) {
              session.recordRealtimeFrame(
                RealtimeFrame.text(
                  id: 'w-$workerId-$seq',
                  sessionId: 'session-$workerId',
                  direction: FrameDirection.incoming,
                  text: 'in-flight data $seq',
                ),
              );
              totalRecorded++;
              seq++;
              await Future<void>.delayed(Duration.zero);
            }
          }),
        );

        // Allow some frames to accumulate
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(totalRecorded, greaterThan(0));

        // 1. Concurrent clear() during active in-flight recording
        await expectLater(session.clear(), completes);

        // Allow more recording after clear
        await Future<void>.delayed(const Duration(milliseconds: 30));

        // 2. Concurrent dispose() during active in-flight recording
        await expectLater(session.dispose(), completes);

        // Stop background workers and await completion
        recording = false;
        await workers;

        // 3. Post-dispose safety: recording more frames must not throw
        expect(
          () => session.recordRealtimeFrame(
            RealtimeFrame.text(
              id: 'post-dispose-frame',
              sessionId: 'session-0',
              direction: FrameDirection.incoming,
              text: 'after dispose',
            ),
          ),
          returnsNormally,
        );

        // 4. Querying frames after dispose returns empty list without error
        expect(session.getRealtimeFrames('session-0'), isEmpty);
        expect(session.isDisposed, isTrue);
      },
    );
  });
}
