// ignore_for_file: invalid_use_of_internal_member
@Tags(['stress'])
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';

void main() {
  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('Realtime Message Storm & Throughput Stress Tests', () {
    test(
      'Test 1: 10 concurrent sessions x 1,000 frames (10,000 frames total) - bounds & FIFO eviction',
      () async {
        const capacity = 500;
        final session = InterceptlyEngine(
          settings: const InterceptlySettings(maxFramesPerSession: capacity),
        );
        addTearDown(session.dispose);

        const sessionCount = 10;
        const framesPerSession = 1000;

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

              if (fIndex % 100 == 0) {
                await Future<void>.delayed(Duration.zero);
              }
            }
          }),
        );

        for (var sIndex = 0; sIndex < sessionCount; sIndex++) {
          final sessionId = 'storm-session-$sIndex';
          final frames = session.getRealtimeFrames(sessionId);

          expect(
            frames.length,
            equals(capacity),
            reason: 'Session $sessionId must contain exactly $capacity frames',
          );

          final expectedStartSeq = framesPerSession - capacity;
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
        final session = InterceptlyEngine(
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
          final session = InterceptlyEngine(
            settings: const InterceptlySettings(maxFramesPerSession: 1000),
          );
          addTearDown(session.dispose);

          var notifyCount = 0;
          session.addListener(() => notifyCount++);

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

          expect(
            notifyCount,
            equals(0),
            reason: 'Zero notifications during active frame storm burst',
          );

          async.elapse(const Duration(milliseconds: 49));
          expect(notifyCount, equals(0));

          async.elapse(const Duration(milliseconds: 15));
          expect(
            notifyCount,
            equals(1),
            reason:
                'Burst of 1,000 frames must trigger exactly 1 batched notification',
          );

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

          expect(
            notifyCount,
            inInclusiveRange(4, 7),
            reason:
                'Sustained storm must batch notifications at ~100ms intervals',
          );

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
        final session = InterceptlyEngine(
          settings: const InterceptlySettings(maxFramesPerSession: 500),
        );

        var recording = true;
        var totalRecorded = 0;

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

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(totalRecorded, greaterThan(0));

        await expectLater(session.clear(), completes);

        await Future<void>.delayed(const Duration(milliseconds: 30));

        await expectLater(session.dispose(), completes);

        recording = false;
        await workers;

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

        expect(session.getRealtimeFrames('session-0'), isEmpty);
        expect(session.isDisposed, isTrue);
      },
    );
  });
}
