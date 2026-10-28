// ignore_for_file: invalid_use_of_internal_member

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/realtime_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Realtime epoch regression', () {
    setUp(() async {
      await Interceptly.resetForTesting();
    });

    tearDown(() async {
      await Interceptly.resetForTesting();
    });

    test('loadPayload after reset returns expired not new bytes', () async {
      final store = RealtimeStore(
        maxFramesPerSession: 100,
        onThrottledBatch: () {},
      );
      addTearDown(store.dispose);

      await store.ensureDiskStorageInitialized(
        persistToDisk: true,
        engineId: 'epoch-reg',
      );

      final bytesA = Uint8List.fromList(List.filled(2048, 0xAA));
      await store.recordFrame(
        RealtimeFrame.binary(
          id: 'epoch-a',
          sessionId: 'epoch-sess',
          direction: FrameDirection.incoming,
          bytes: bytesA,
        ),
        persistToDisk: true,
        offloadThreshold: 1024,
        engineId: 'epoch-reg',
      );

      final framesBefore = store.getRealtimeFrames('epoch-sess');
      expect(framesBefore, isNotEmpty);
      final oldFrame = framesBefore.firstWhere((f) => f.id == 'epoch-a');
      expect(oldFrame.location, equals(BodyLocation.file));
      final oldRotation = oldFrame.rotationCount ?? 0;

      await store.resetDiskStorage();
      expect(store.bodyStore.rotationCount, greaterThan(oldRotation));

      final bytesB = Uint8List.fromList(List.filled(2048, 0xBB));
      await store.recordFrame(
        RealtimeFrame.binary(
          id: 'epoch-b',
          sessionId: 'epoch-sess',
          direction: FrameDirection.incoming,
          bytes: bytesB,
        ),
        persistToDisk: true,
        offloadThreshold: 1024,
        engineId: 'epoch-reg',
      );

      final loaded = await store.loadPayload(oldFrame);
      expect(loaded, isA<String>());
      expect(loaded as String, contains('expired'));
      expect(loaded, isNot(contains('BB')));
    });

    test('resetFile increments rotation generation', () async {
      final store = RealtimeStore(
        maxFramesPerSession: 100,
        onThrottledBatch: () {},
      );
      addTearDown(store.dispose);

      await store.ensureDiskStorageInitialized(
        persistToDisk: true,
        engineId: 'epoch-incr',
      );

      final before = store.bodyStore.rotationCount;
      await store.resetDiskStorage();
      expect(store.bodyStore.rotationCount, equals(before + 1));
      await store.resetDiskStorage();
      expect(store.bodyStore.rotationCount, equals(before + 2));
    });

    test('concurrent read during reset yields expired not torn bytes',
        () async {
      final store = RealtimeStore(
        maxFramesPerSession: 100,
        onThrottledBatch: () {},
      );
      addTearDown(store.dispose);

      await store.ensureDiskStorageInitialized(
        persistToDisk: true,
        engineId: 'epoch-torn',
      );

      final dir = Directory.systemTemp;
      expect(store.bodyStore.isInitialized, isTrue);

      final bytesA = Uint8List.fromList(List.filled(1024, 0x11));
      final ref = await store.bodyStore.append(bytesA);
      final oldFrame = RealtimeFrame.offloaded(
        id: 'torn-old',
        sessionId: 'torn-sess',
        direction: FrameDirection.incoming,
        type: FrameType.binary,
        payloadSizeBytes: ref.$2,
        shortPreview: 'old',
        fileOffset: ref.$1,
        fileLength: ref.$2,
        rotationCount: ref.$3,
      );

      final readFuture = store.loadPayload(oldFrame);
      await store.resetDiskStorage();
      final bytesB = Uint8List.fromList(List.filled(1024, 0x22));
      await store.bodyStore.append(bytesB);

      final loaded = await readFuture;
      if (loaded is Uint8List) {
        expect(loaded, isNot(equals(bytesB)));
      } else {
        expect(loaded.toString(), contains('expired'));
      }
      expect(dir.existsSync(), isTrue);
    });
  });
}
