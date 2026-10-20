// ignore_for_file: invalid_use_of_internal_member

import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/capture/frame_normalizer.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/engine/realtime_store.dart';

void main() {
  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('InterceptlyEngine Realtime Frame Recording', () {
    test('stores frames accessible via getRealtimeFrames', () {
      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);

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

      engine.recordRealtimeFrame(frame1);
      engine.recordRealtimeFrame(frame2);

      final frames = engine.getRealtimeFrames('ws-100');
      expect(frames.length, equals(2));
      expect(frames[0].id, equals('f-1'));
      expect(frames[0].textPayload, equals('{"event":"connected"}'));
      expect(frames[1].id, equals('f-2'));
      expect(frames[1].textPayload, equals('{"action":"subscribe"}'));

      expect(engine.getRealtimeFrames('ws-unknown'), isEmpty);
    });

    test('isolates frames across distinct sessions', () {
      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);

      engine.recordRealtimeFrame(
        RealtimeFrame.text(
          id: 'f-a1',
          sessionId: 'session-a',
          direction: FrameDirection.incoming,
          text: 'a1',
        ),
      );
      engine.recordRealtimeFrame(
        RealtimeFrame.text(
          id: 'f-b1',
          sessionId: 'session-b',
          direction: FrameDirection.outgoing,
          text: 'b1',
        ),
      );

      expect(engine.getRealtimeFrames('session-a').length, equals(1));
      expect(engine.getRealtimeFrames('session-a').first.id, equals('f-a1'));
      expect(engine.getRealtimeFrames('session-b').length, equals(1));
      expect(engine.getRealtimeFrames('session-b').first.id, equals('f-b1'));
    });

    test('ignores frames when engine is disabled and resumes on enable', () {
      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);

      engine.disable();
      expect(engine.isEnabled, isFalse);

      engine.recordRealtimeFrame(
        RealtimeFrame.text(
          id: 'f-dropped',
          sessionId: 'ws-drop',
          direction: FrameDirection.incoming,
          text: 'should be dropped',
        ),
      );

      expect(engine.getRealtimeFrames('ws-drop'), isEmpty);

      engine.enable();
      expect(engine.isEnabled, isTrue);

      engine.recordRealtimeFrame(
        RealtimeFrame.text(
          id: 'f-kept',
          sessionId: 'ws-drop',
          direction: FrameDirection.incoming,
          text: 'should be kept',
        ),
      );

      expect(engine.getRealtimeFrames('ws-drop').length, equals(1));
      expect(engine.getRealtimeFrames('ws-drop').first.id, equals('f-kept'));
    });
  });

  group('Ring buffer capacity & eviction', () {
    test(
        'drops oldest frames and retains newest when exceeding maxFramesPerSession',
        () {
      final engine = InterceptlyEngine(
        settings: const InterceptlySettings(maxFramesPerSession: 3),
      );
      addTearDown(engine.dispose);

      for (var i = 1; i <= 5; i++) {
        engine.recordRealtimeFrame(
          RealtimeFrame.text(
            id: 'frame-$i',
            sessionId: 'ws-bounded',
            direction: FrameDirection.incoming,
            text: 'payload-$i',
          ),
        );
      }

      final frames = engine.getRealtimeFrames('ws-bounded');
      expect(frames.length, equals(3));
      expect(frames.map((f) => f.id).toList(),
          equals(['frame-3', 'frame-4', 'frame-5']));
      expect(frames.first.id, equals('frame-3'));
      expect(frames.last.id, equals('frame-5'));
    });

    test('retains newest frames when maxFramesPerSession shrinks via configure',
        () {
      final engine = InterceptlyEngine(
        settings: const InterceptlySettings(maxFramesPerSession: 5),
      );
      addTearDown(engine.dispose);

      for (var i = 1; i <= 5; i++) {
        engine.recordRealtimeFrame(
          RealtimeFrame.text(
            id: 'frame-$i',
            sessionId: 'ws-shrink',
            direction: FrameDirection.incoming,
            text: 'payload-$i',
          ),
        );
      }
      expect(engine.getRealtimeFrames('ws-shrink').length, equals(5));

      engine.configure(
        const InterceptlySettings(maxFramesPerSession: 2),
      );

      final shrunk = engine.getRealtimeFrames('ws-shrink');
      expect(shrunk.length, equals(2));
      expect(shrunk.map((f) => f.id).toList(), equals(['frame-4', 'frame-5']));
    });
  });

  group('Message Storm Ticking Throttler', () {
    test(
        'burst of 500 frames within 50ms batches notifyListeners within ~100ms',
        () {
      fakeAsync((async) {
        final engine = InterceptlyEngine(
          settings: const InterceptlySettings(maxFramesPerSession: 100),
        );
        addTearDown(engine.dispose);

        var notifyCount = 0;
        engine.addListener(() => notifyCount++);

        for (var i = 0; i < 500; i++) {
          engine.recordRealtimeFrame(
            RealtimeFrame.text(
              id: 'storm-$i',
              sessionId: 'ws-storm',
              direction:
                  i.isEven ? FrameDirection.incoming : FrameDirection.outgoing,
              text: 'storm message $i',
            ),
          );
          if (i % 10 == 0) {
            async.elapse(const Duration(milliseconds: 1));
          }
        }

        expect(notifyCount, equals(0));

        async.elapse(const Duration(milliseconds: 49));
        expect(notifyCount, equals(0));

        async.elapse(const Duration(milliseconds: 15));
        expect(notifyCount, equals(1));

        async.elapse(const Duration(milliseconds: 200));
        expect(notifyCount, equals(1));

        final retainedFrames = engine.getRealtimeFrames('ws-storm');
        expect(retainedFrames.length, equals(100));
        expect(retainedFrames.first.id, equals('storm-400'));
        expect(retainedFrames.last.id, equals('storm-499'));

        engine.recordRealtimeFrame(
          RealtimeFrame.text(
            id: 'burst2-1',
            sessionId: 'ws-storm',
            direction: FrameDirection.incoming,
            text: 'after idle',
          ),
        );

        async.elapse(const Duration(milliseconds: 50));
        expect(notifyCount, equals(1));

        async.elapse(const Duration(milliseconds: 60));
        expect(notifyCount, equals(2));
      });
    });
  });

  group('InterceptlyEngine Lifecycle: clear and dispose', () {
    test('clear wipes stored realtime frames and cancels throttler timer', () {
      fakeAsync((async) {
        final engine = InterceptlyEngine();
        addTearDown(engine.dispose);

        engine.recordRealtimeFrame(
          RealtimeFrame.text(
            id: 'f-clear',
            sessionId: 'ws-clear',
            direction: FrameDirection.incoming,
            text: 'to be cleared',
          ),
        );
        expect(engine.getRealtimeFrames('ws-clear').length, equals(1));

        var notifyCount = 0;
        engine.addListener(() => notifyCount++);

        engine.clear();
        expect(engine.getRealtimeFrames('ws-clear'), isEmpty);
        expect(notifyCount, equals(1));

        async.elapse(const Duration(milliseconds: 200));
        expect(notifyCount, equals(1));
      });
    });

    test('dispose cancels throttler timer cleanly and releases frames', () {
      fakeAsync((async) {
        final store = RealtimeStore(
          maxFramesPerSession: 100,
          onThrottledBatch: () {},
        );

        store.recordFrame(
          RealtimeFrame.text(
            id: 'f-dispose',
            sessionId: 'ws-dispose',
            direction: FrameDirection.incoming,
            text: 'to be disposed',
          ),
        );
        expect(store.getRealtimeFrames('ws-dispose').length, equals(1));

        store.dispose();
        expect(store.getRealtimeFrames('ws-dispose'), isEmpty);

        expect(
          () => async.elapse(const Duration(milliseconds: 200)),
          returnsNormally,
        );
      });
    });
  });

  group('Interceptly Facade Forwarders', () {
    test('recordRealtimeFrame and getRealtimeFrames forward to engine', () {
      final engine = InterceptlyEngine.instance;

      final frame = RealtimeFrame.text(
        id: 'f-facade',
        sessionId: 'ws-facade',
        direction: FrameDirection.incoming,
        text: 'hello via facade',
      );

      engine.recordRealtimeFrame(frame);

      expect(engine.getRealtimeFrames('ws-facade').length, equals(1));
      expect(
          engine.getRealtimeFrames('ws-facade').first.id, equals('f-facade'));
    });

    test(
        'recordRealtimeConnection and closeRealtimeConnection update session entries',
        () {
      final engine = InterceptlyEngine.instance;

      engine.recordRealtimeConnection(
        id: 'conn-1',
        url: 'wss://echo.example.com/ws',
        headers: {'sec-websocket-protocol': 'chat'},
      );

      expect(engine.entries.length, equals(1));
      expect(engine.entries.first.id, equals('conn-1'));
      expect(engine.entries.first.method, equals('WS'));
      expect(engine.entries.first.url, equals('wss://echo.example.com/ws'));
      expect(engine.entries.first.statusCode, equals(0));

      engine.closeRealtimeConnection('conn-1', closeCode: 1000);

      expect(engine.entries.first.statusCode, equals(1000));
      expect(engine.entries.first.hasError, isFalse);
    });
  });

  group('Realtime Stream Hardening', () {
    test('binary payload uses zero-copy reference without unnecessary cloning',
        () {
      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);
      final collector = DefaultRealtimeTrafficCollector(engine: engine);

      final originalBytes = Uint8List.fromList([10, 20, 30, 40]);
      collector.recordFrame(
        sessionId: 'ws-alias',
        direction: FrameDirection.incoming,
        type: FrameType.binary,
        payload: originalBytes,
      );

      final storedFrames = engine.getRealtimeFrames('ws-alias');
      expect(storedFrames.length, equals(1));
      expect(identical(storedFrames.first.binaryPayload, originalBytes), isTrue,
          reason: 'Binary payload should be zero-copy');
    });

    test('truncates binary and text payload according to maxBodyBytes', () {
      final engine = InterceptlyEngine(
        settings: const InterceptlySettings(maxBodyBytes: 8),
      );
      addTearDown(engine.dispose);
      final collector = DefaultRealtimeTrafficCollector(engine: engine);

      final binaryData = Uint8List.fromList(List.generate(16, (i) => i));
      collector.recordFrame(
        sessionId: 'ws-trunc',
        direction: FrameDirection.incoming,
        type: FrameType.binary,
        payload: binaryData,
      );

      collector.recordFrame(
        sessionId: 'ws-trunc',
        direction: FrameDirection.outgoing,
        type: FrameType.text,
        payload: '12345678901234567890',
      );

      final frames = engine.getRealtimeFrames('ws-trunc');
      expect(frames.length, equals(2));

      expect(frames[0].binaryPayload!.length, equals(8));
      expect(frames[0].payloadSizeBytes, equals(16),
          reason: 'Retains original payload size');

      expect(frames[1].textPayload!.length, equals(8));
      expect(frames[1].payloadSizeBytes, equals(20),
          reason: 'Retains original payload size');
    });

    test('respects shouldCapture filter for realtime connections', () {
      final engine = InterceptlyEngine(
        settings: InterceptlySettings(
          shouldCapture: (url) => !url.contains('health-check'),
        ),
      );
      addTearDown(engine.dispose);
      final collector = DefaultRealtimeTrafficCollector(engine: engine);

      collector.recordConnection(
        sessionId: 'ignored-session',
        uri: Uri.parse('wss://example.com/health-check'),
      );
      collector.recordConnection(
        sessionId: 'captured-session',
        uri: Uri.parse('wss://example.com/stream'),
      );

      expect(engine.entries.length, equals(1));
      expect(engine.entries.first.id, equals('captured-session'));
    });

    test('RealtimeStore bounds sessions to max 50 using LRU eviction', () {
      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);

      for (var i = 0; i < 55; i++) {
        engine.recordRealtimeFrame(
          RealtimeFrame.text(
            id: 'frame-$i',
            sessionId: 'sess-$i',
            direction: FrameDirection.incoming,
            text: 'msg-$i',
          ),
        );
      }

      for (var i = 0; i < 5; i++) {
        expect(engine.getRealtimeFrames('sess-$i'), isEmpty,
            reason: 'sess-$i should be evicted');
      }

      for (var i = 5; i < 55; i++) {
        expect(engine.getRealtimeFrames('sess-$i').length, equals(1),
            reason: 'sess-$i should be retained');
      }
    });

    test('RealtimeFrame calculates utf8 byte length without allocating', () {
      final asciiFrame = RealtimeFrame(
        id: '1',
        sessionId: 's',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        textPayload: 'hello',
      );
      expect(asciiFrame.payloadSizeBytes, equals(5));

      final multiByteFrame = RealtimeFrame(
        id: '2',
        sessionId: 's',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        textPayload: 'Xin chào thế giới 🌍',
      );
      expect(multiByteFrame.payloadSizeBytes, equals(27));
    });

    test('tracks and increments frame counts correctly across directions', () {
      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);

      expect(engine.getRealtimeFrameCounts('ws-count').incoming, equals(0));
      expect(engine.getRealtimeFrameCounts('ws-count').outgoing, equals(0));
      expect(engine.getRealtimeFrameCounts('ws-count').total, equals(0));

      engine.recordRealtimeFrame(
        RealtimeFrame.text(
          id: 'f-in-1',
          sessionId: 'ws-count',
          direction: FrameDirection.incoming,
          text: 'msg1',
        ),
      );
      engine.recordRealtimeFrame(
        RealtimeFrame.text(
          id: 'f-in-2',
          sessionId: 'ws-count',
          direction: FrameDirection.incoming,
          text: 'msg2',
        ),
      );
      engine.recordRealtimeFrame(
        RealtimeFrame.text(
          id: 'f-out-1',
          sessionId: 'ws-count',
          direction: FrameDirection.outgoing,
          text: 'msg3',
        ),
      );

      final counts = engine.getRealtimeFrameCounts('ws-count');
      expect(counts.incoming, equals(2));
      expect(counts.outgoing, equals(1));
      expect(counts.total, equals(3));

      engine.clear();
      expect(engine.getRealtimeFrameCounts('ws-count').total, equals(0));
    });
  });

  group('Clean-Sheet RealtimeFrame Model & Settings', () {
    test(
        'shortPreview cuts cleanly at 128 chars without splitting surrogate pairs',
        () {
      final longText = 'a' * 150;
      final preview =
          RealtimeFrame.extractShortPreview(longText, FrameType.text);
      expect(preview.length, equals(128));
      expect(preview, equals('a' * 128));

      final textWithEmoji = '${'a' * 126}🌍🚀${'b' * 50}';
      final emojiPreview =
          RealtimeFrame.extractShortPreview(textWithEmoji, FrameType.text);
      expect(emojiPreview.length, equals(128));
      expect(emojiPreview.endsWith('🌍'), isTrue,
          reason: 'Must not split the surrogate pair of 🚀');

      final binaryData =
          Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02]);
      final binaryPreview =
          RealtimeFrame.extractShortPreview(binaryData, FrameType.binary);
      expect(binaryPreview, contains('binary: 6 bytes'));
      expect(binaryPreview, contains('de ad be ef'));
    });

    test('RealtimeFrame.offloaded holds file location and null payloads in RAM',
        () {
      final frame = RealtimeFrame.offloaded(
        id: 'frame-off-1',
        sessionId: 'ws-conn',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        payloadSizeBytes: 65536,
        shortPreview: '{"initial_sync": true...',
        fileOffset: 1024,
        fileLength: 65536,
        rotationCount: 2,
      );

      expect(frame.location, equals(BodyLocation.file));
      expect(frame.textPayload, isNull);
      expect(frame.binaryPayload, isNull);
      expect(frame.shortPreview, equals('{"initial_sync": true...'));
      expect(frame.fileOffset, equals(1024));
      expect(frame.fileLength, equals(65536));
      expect(frame.rotationCount, equals(2));
      expect(frame.payloadSizeBytes, equals(65536));
    });

    test('RealtimeFrame.memoryText and memoryBinary hold inline payloads', () {
      final textFrame = RealtimeFrame.memoryText(
        id: 'f-txt',
        sessionId: 'ws-conn',
        direction: FrameDirection.outgoing,
        text: 'hello world',
      );
      expect(textFrame.location, equals(BodyLocation.memory));
      expect(textFrame.textPayload, equals('hello world'));
      expect(textFrame.shortPreview, equals('hello world'));
      expect(textFrame.fileOffset, isNull);

      final binFrame = RealtimeFrame.memoryBinary(
        id: 'f-bin',
        sessionId: 'ws-conn',
        direction: FrameDirection.incoming,
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(binFrame.location, equals(BodyLocation.memory));
      expect(binFrame.binaryPayload, equals(Uint8List.fromList([1, 2, 3])));
      expect(binFrame.shortPreview, contains('binary: 3 bytes'));
    });

    test(
        'InterceptlySettings includes realtimeBodyOffloadThreshold and maxTotalRealtimeFrames',
        () {
      const defaultSettings = InterceptlySettings();
      expect(defaultSettings.realtimeBodyOffloadThreshold, equals(32 * 1024));
      expect(defaultSettings.maxTotalRealtimeFrames, equals(5000));

      final customSettings = defaultSettings.copyWith(
        realtimeBodyOffloadThreshold: 64 * 1024,
        maxTotalRealtimeFrames: 10000,
      );
      expect(customSettings.realtimeBodyOffloadThreshold, equals(64 * 1024));
      expect(customSettings.maxTotalRealtimeFrames, equals(10000));
    });
  });

  group('FrameNormalizer & Ingestion Pipeline', () {
    test(
        'text payload computes byte size via utf8ByteLength with 0 heap byte allocations',
        () {
      const text = 'Hello world! 🚀 12345';
      final normalized = FrameNormalizer.normalize(
        text,
        offloadThreshold: 32 * 1024,
        maxBodyBytes: 1024,
      );
      expect(normalized.type, equals(FrameType.text));
      expect(normalized.originalSizeBytes, equals(utf8ByteLength(text)));
      expect(normalized.payload, equals(text));
      expect(normalized.shouldOffload, isFalse);
      expect(normalized.shortPreview, equals(text));
    });

    test('binary payload passed as Uint8List is not cloned via fromList', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final normalized = FrameNormalizer.normalize(
        bytes,
        offloadThreshold: 32 * 1024,
        maxBodyBytes: 1024,
      );
      expect(normalized.type, equals(FrameType.binary));
      expect(identical(normalized.payload, bytes), isTrue,
          reason: 'Must not clone Uint8List');
      expect(normalized.originalSizeBytes, equals(5));
      expect(normalized.shouldOffload, isFalse);
    });

    test('payloads exceeding offloadThreshold are marked shouldOffload = true',
        () {
      final largeText = 'a' * 40000;
      final normalized = FrameNormalizer.normalize(
        largeText,
        offloadThreshold: 32 * 1024,
        maxBodyBytes: 100 * 1024,
      );
      expect(normalized.shouldOffload, isTrue);
      expect(normalized.originalSizeBytes, equals(40000));
      expect(normalized.shortPreview.length, equals(128));
    });

    test(
        'handshake shouldCapture predicate is evaluated once and cached on RealtimeSessionScope',
        () {
      var checkCount = 0;
      final settings = InterceptlySettings(
        shouldCapture: (url) {
          checkCount++;
          return url.contains('allowed');
        },
      );
      final engine = InterceptlyEngine(settings: settings);
      final collector = DefaultRealtimeTrafficCollector(engine: engine);

      final droppedScope =
          collector.openSession(uri: Uri.parse('wss://example.com/blocked'));
      expect(checkCount, equals(1));

      droppedScope.send('hello');
      droppedScope.receive('world');
      expect(checkCount, equals(1),
          reason:
              'Predicate must be cached and evaluated once per connection handshake');
      expect(engine.getRealtimeFrames(droppedScope.sessionId), isEmpty);

      final allowedScope =
          collector.openSession(uri: Uri.parse('wss://example.com/allowed'));
      expect(checkCount, equals(2));
      allowedScope.send('msg1');
      expect(checkCount, equals(2));
    });

    test(
        'normalizes Map payload into canonical JSON text frame with accurate byte size',
        () {
      final payload = {
        'event': 'message',
        'data': {'userId': 42, 'active': true}
      };
      final normalized = FrameNormalizer.normalize(
        payload,
        offloadThreshold: 32 * 1024,
        maxBodyBytes: 1024,
      );
      expect(normalized.type, equals(FrameType.text));
      expect(normalized.payload,
          equals('{"event":"message","data":{"userId":42,"active":true}}'));
      expect(normalized.originalSizeBytes,
          equals(utf8.encode(normalized.payload as String).length));
      expect(normalized.shortPreview, contains('{"event":"message"'));
    });

    test('normalizes List payload into canonical JSON array text frame', () {
      final payload = [
        'chat_message',
        {'text': 'hi'}
      ];
      final normalized = FrameNormalizer.normalize(
        payload,
        offloadThreshold: 32 * 1024,
        maxBodyBytes: 1024,
      );
      expect(normalized.type, equals(FrameType.text));
      expect(normalized.payload, equals('["chat_message",{"text":"hi"}]'));
    });

    test(
        'falls back gracefully to toString() if Map/List contains circular reference or fails to encode',
        () {
      final cyclicList = <dynamic>[];
      cyclicList.add(cyclicList);
      final normalized = FrameNormalizer.normalize(
        cyclicList,
        offloadThreshold: 32 * 1024,
        maxBodyBytes: 1024,
      );
      expect(normalized.type, equals(FrameType.text));
      expect(normalized.payload, contains('[...]'));
    });

    test(
        'FrameNormalizer attaches pre-encoded bytes for frames >= offloadThreshold',
        () {
      final largeJson = jsonEncode({'data': 'x' * 35000});
      final normalized = FrameNormalizer.normalize(
        largeJson,
        offloadThreshold: 32 * 1024,
        maxBodyBytes: 100 * 1024,
      );
      expect(normalized.shouldOffload, isTrue);
      expect(normalized.preEncodedBytes, isNotNull);
      expect(normalized.preEncodedBytes!.length,
          equals(normalized.originalSizeBytes));
    });

    test(
        'FrameNormalizer truncates binary frame with dedicated slice and does not retain backing buffer',
        () {
      final bigBuffer = Uint8List(2000);
      final normalized = FrameNormalizer.normalize(
        bigBuffer,
        offloadThreshold: 0,
        maxBodyBytes: 100,
      );
      final payload = normalized.payload as Uint8List;
      expect(payload.length, equals(100));
      expect(payload.buffer.lengthInBytes, equals(100));
    });
  });

  group(
      'Clean-Sheet RealtimeStore with Dynamic Circular Buffer & Global Budget',
      () {
    test(
        'dynamic circular buffer starts small and expands up to maxFramesPerSession',
        () {
      final store = RealtimeStore(
        maxFramesPerSession: 64,
        onThrottledBatch: () {},
      );
      addTearDown(store.dispose);

      for (var i = 0; i < 20; i++) {
        store.recordFrame(RealtimeFrame.text(
          id: 'f-$i',
          sessionId: 'ws-grow',
          direction: FrameDirection.incoming,
          text: 'msg-$i',
        ));
      }

      final frames = store.getRealtimeFrames('ws-grow');
      expect(frames.length, equals(20));
      expect(frames.first.id, equals('f-0'));
      expect(frames.last.id, equals('f-19'));

      for (var i = 20; i < 70; i++) {
        store.recordFrame(RealtimeFrame.text(
          id: 'f-$i',
          sessionId: 'ws-grow',
          direction: FrameDirection.incoming,
          text: 'msg-$i',
        ));
      }
      expect(frames.length, equals(64));
      expect(frames.first.id, equals('f-6'));
      expect(frames.last.id, equals('f-69'));
    });

    test(
        'replaceById in DynamicCircularBuffer finds newest element in reverse search',
        () {
      final buf = DynamicCircularBuffer(maxCapacity: 100);
      for (var i = 0; i < 50; i++) {
        buf.add(RealtimeFrame.text(
            id: 'f-$i',
            sessionId: 's',
            direction: FrameDirection.incoming,
            text: 't'));
      }
      final updated = RealtimeFrame.text(
          id: 'f-49',
          sessionId: 's',
          direction: FrameDirection.incoming,
          text: 'updated');
      expect(buf.replaceById('f-49', updated), isTrue);
      expect(buf[49].textPayload, equals('updated'));
    });

    test('getRealtimeFrames returns live zero-allocation ListBase view', () {
      final store = RealtimeStore(
        maxFramesPerSession: 100,
        onThrottledBatch: () {},
      );
      addTearDown(store.dispose);

      final view1 = store.getRealtimeFrames('ws-view');
      final view2 = store.getRealtimeFrames('ws-view');
      expect(identical(view1, view2), isTrue,
          reason: 'Must return cached zero-alloc view');
      expect(view1.length, equals(0));

      store.recordFrame(RealtimeFrame.text(
        id: 'f-1',
        sessionId: 'ws-view',
        direction: FrameDirection.incoming,
        text: 'hello',
      ));

      expect(view1.length, equals(1));
      expect(view1[0].id, equals('f-1'));
      expect(() => view1[0] = view1[0], throwsUnsupportedError);
    });

    test(
        'global coordinator prioritizes closed sessions during budget eviction',
        () {
      final store = RealtimeStore(
        maxFramesPerSession: 50,
        maxTotalRealtimeFrames: 40,
        onThrottledBatch: () {},
      );
      addTearDown(store.dispose);

      for (var i = 0; i < 20; i++) {
        store.recordFrame(RealtimeFrame.text(
          id: 'a-$i',
          sessionId: 'session-a',
          direction: FrameDirection.incoming,
          text: 'a-$i',
        ));
      }

      for (var i = 0; i < 20; i++) {
        store.recordFrame(RealtimeFrame.text(
          id: 'b-$i',
          sessionId: 'session-b',
          direction: FrameDirection.incoming,
          text: 'b-$i',
        ));
      }
      store.markSessionClosed('session-b');

      expect(store.getRealtimeFrames('session-a').length, equals(20));
      expect(store.getRealtimeFrames('session-b').length, equals(20));

      for (var i = 20; i < 30; i++) {
        store.recordFrame(RealtimeFrame.text(
          id: 'a-$i',
          sessionId: 'session-a',
          direction: FrameDirection.incoming,
          text: 'a-$i',
        ));
      }

      expect(store.getRealtimeFrames('session-a').length, equals(30),
          reason: 'Active session frames must be protected');
      expect(store.getRealtimeFrames('session-b').length, equals(10),
          reason: 'Closed session frames must be prioritized for eviction');
    });

    test('getRealtimeFrames does not pollute or mutate LRU session order', () {
      final store = RealtimeStore(
          maxFramesPerSession: 10, maxSessions: 3, onThrottledBatch: () {});
      addTearDown(store.dispose);

      store.recordFrame(RealtimeFrame.text(
          id: '1',
          sessionId: 's1',
          direction: FrameDirection.incoming,
          text: 'm'));
      store.recordFrame(RealtimeFrame.text(
          id: '2',
          sessionId: 's2',
          direction: FrameDirection.incoming,
          text: 'm'));
      store.recordFrame(RealtimeFrame.text(
          id: '3',
          sessionId: 's3',
          direction: FrameDirection.incoming,
          text: 'm'));

      store.getRealtimeFrames('s1');

      store.recordFrame(RealtimeFrame.text(
          id: '4',
          sessionId: 's4',
          direction: FrameDirection.incoming,
          text: 'm'));

      expect(store.getRealtimeFrames('s1'), isEmpty,
          reason: 's1 must be evicted because read does not refresh LRU');
      expect(store.getRealtimeFrames('s2').length, equals(1));
      expect(store.getRealtimeFrames('s3').length, equals(1));
      expect(store.getRealtimeFrames('s4').length, equals(1));
    });

    test(
        'reading non-existent session does not allocate buffer or count towards maxSessions',
        () {
      final store = RealtimeStore(
          maxFramesPerSession: 10, maxSessions: 2, onThrottledBatch: () {});
      addTearDown(store.dispose);

      final emptyView = store.getRealtimeFrames('ghost-session');
      expect(emptyView, isEmpty);

      store.recordFrame(RealtimeFrame.text(
          id: '1',
          sessionId: 's1',
          direction: FrameDirection.incoming,
          text: 'm'));
      store.recordFrame(RealtimeFrame.text(
          id: '2',
          sessionId: 's2',
          direction: FrameDirection.incoming,
          text: 'm'));

      expect(store.getRealtimeFrames('s1').length, equals(1));
      expect(store.getRealtimeFrames('s2').length, equals(1));
    });

    test(
        'ValueNotifier coalesces frame counts and notifies once per throttle window during message bursts',
        () {
      fakeAsync((async) {
        final store =
            RealtimeStore(maxFramesPerSession: 100, onThrottledBatch: () {});
        addTearDown(store.dispose);

        final notifier = store.getFrameCountsNotifier('ws-burst');
        var notifyCount = 0;
        notifier.addListener(() => notifyCount++);

        for (var i = 0; i < 50; i++) {
          store.recordFrame(RealtimeFrame.text(
            id: 'f-$i',
            sessionId: 'ws-burst',
            direction: FrameDirection.incoming,
            text: 'msg',
          ));
        }

        expect(store.getFrameCounts('ws-burst').incoming, equals(50));
        expect(notifyCount, equals(0),
            reason: 'Must not synchronously thrash notifier on every frame');

        async.elapse(const Duration(milliseconds: 100));
        expect(notifyCount, equals(1),
            reason: 'Must notify exactly once for the burst batch');
        expect(notifier.value.incoming, equals(50));
      });
    });

    test(
        'frame arrival notifies only that session ValueNotifier<RealtimeFrameCounts>',
        () {
      fakeAsync((async) {
        final store = RealtimeStore(
          maxFramesPerSession: 100,
          onThrottledBatch: () {},
        );
        addTearDown(store.dispose);

        final notifierA = store.getFrameCountsNotifier('sess-a');
        final notifierB = store.getFrameCountsNotifier('sess-b');

        var aNotified = 0;
        var bNotified = 0;

        notifierA.addListener(() => aNotified++);
        notifierB.addListener(() => bNotified++);

        store.recordFrame(RealtimeFrame.text(
          id: 'f-a1',
          sessionId: 'sess-a',
          direction: FrameDirection.incoming,
          text: 'msg',
        ));

        expect(store.getFrameCounts('sess-a').incoming, equals(1));
        expect(aNotified, equals(0), reason: 'Must coalesce to throttle timer');

        async.elapse(const Duration(milliseconds: 100));

        expect(aNotified, equals(1));
        expect(bNotified, equals(0),
            reason: 'Unrelated session must not be notified');
        expect(notifierA.value.incoming, equals(1));
      });
    });
  });

  group('RealtimeBodyStore Integration & Async Lazy Load in InterceptlyEngine',
      () {
    test('frames >= 32 KB are offloaded to temp file and lazy-loaded',
        () async {
      final engine = InterceptlyEngine(
        settings: const InterceptlySettings(
          realtimeBodyOffloadThreshold: 32 * 1024,
        ),
      );
      addTearDown(engine.dispose);

      const smallText = 'hello world';
      final largeText = 'a' * (40 * 1024);

      engine.recordRealtimeConnection(
        id: 'ws-offload',
        url: 'wss://example.com/ws',
      );

      await engine.recordRealtimeFrame(RealtimeFrame.text(
        id: 'f-small',
        sessionId: 'ws-offload',
        direction: FrameDirection.incoming,
        text: smallText,
      ));

      await engine.recordRealtimeFrame(RealtimeFrame.text(
        id: 'f-large',
        sessionId: 'ws-offload',
        direction: FrameDirection.incoming,
        text: largeText,
      ));

      final frames = engine.getRealtimeFrames('ws-offload');
      expect(frames.length, equals(2));

      expect(frames[0].location, equals(BodyLocation.memory));
      expect(frames[0].textPayload, equals(smallText));
      final loadedSmall = await engine.loadRealtimePayload(frames[0]);
      expect(loadedSmall, equals(smallText));

      expect(frames[1].location, equals(BodyLocation.file));
      expect(frames[1].textPayload, isNull);
      expect(frames[1].fileOffset, isNotNull);
      expect(frames[1].fileLength, equals(40 * 1024));

      final loadedLarge = await engine.loadRealtimePayload(frames[1]);
      expect(loadedLarge, equals(largeText));
    });

    test('large binary frame is offloaded and loaded back as Uint8List',
        () async {
      final engine = InterceptlyEngine(
        settings: const InterceptlySettings(
          realtimeBodyOffloadThreshold: 1024,
        ),
      );
      addTearDown(engine.dispose);

      final largeBytes =
          Uint8List.fromList(List.generate(2048, (i) => i % 256));

      engine.recordRealtimeConnection(
        id: 'ws-bin-off',
        url: 'wss://example.com/bin',
      );

      await engine.recordRealtimeFrame(RealtimeFrame.binary(
        id: 'f-bin-large',
        sessionId: 'ws-bin-off',
        direction: FrameDirection.outgoing,
        bytes: largeBytes,
      ));

      final frames = engine.getRealtimeFrames('ws-bin-off');
      expect(frames.length, equals(1));
      expect(frames[0].location, equals(BodyLocation.file));
      expect(frames[0].binaryPayload, isNull);

      final loaded = await engine.loadRealtimePayload(frames[0]);
      expect(loaded, isA<Uint8List>());
      expect(loaded, equals(largeBytes));
    });

    test(
        'expired frame returns graceful expiration placeholder after file rotation',
        () async {
      final store = RealtimeStore(
        maxFramesPerSession: 100,
        onThrottledBatch: () {},
      );
      addTearDown(store.dispose);

      await store.ensureDiskStorageInitialized(
        persistToDisk: true,
        engineId: 'ws-rot',
      );

      await store.recordFrame(
        RealtimeFrame.text(
          id: 'f-rot',
          sessionId: 'ws-rot',
          direction: FrameDirection.incoming,
          text: 'x' * 2048,
        ),
        persistToDisk: true,
        offloadThreshold: 1024,
        engineId: 'ws-rot',
      );

      final frames = store.getRealtimeFrames('ws-rot');
      final frame = frames.first;
      expect(frame.location, equals(BodyLocation.file));

      await store.bodyStore.rotate();

      final result = await store.loadPayload(frame);
      expect(result, contains('expired due to file rotation'));
    });

    test(
        'clear resets realtime tmp file without touching REST session tmp file',
        () async {
      final store = RealtimeStore(
        maxFramesPerSession: 100,
        onThrottledBatch: () {},
      );
      addTearDown(store.dispose);

      await store.ensureDiskStorageInitialized(
        persistToDisk: true,
        engineId: 'ws-clear',
      );

      await store.recordFrame(
        RealtimeFrame.text(
          id: 'f-clear',
          sessionId: 'ws-clear',
          direction: FrameDirection.incoming,
          text: 'c' * 2048,
        ),
        persistToDisk: true,
        offloadThreshold: 1024,
        engineId: 'ws-clear',
      );

      expect(store.getRealtimeFrames('ws-clear').length, equals(1));

      store.clear();
      await store.resetDiskStorage();
      expect(store.getRealtimeFrames('ws-clear'), isEmpty);
      expect(store.bodyStore.currentOffset, equals(0));
    });
  });
}
