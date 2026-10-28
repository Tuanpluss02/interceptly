// ignore_for_file: invalid_use_of_internal_member

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/capture/frame_normalizer.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly_socket_io/interceptly_socket_io.dart';

import 'test_helpers/fake_socket.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InterceptlyEngine engine;

  setUp(() async {
    await Interceptly.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp('socket_io_lifecycle_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      },
    );
    engine = InterceptlyEngine.instance;
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Socket.IO lifecycle regression', () {
    test('double attach does not duplicate sessions or listeners', () async {
      final socket = FakeSocket(uri: 'http://localhost:3000');
      final first = InterceptlySocketIo.attach(
        socket,
        sessionId: 'dup-1',
      );
      final second = InterceptlySocketIo.attach(
        socket,
        sessionId: 'dup-2',
      );

      expect(identical(first, second), isTrue);
      expect(engine.entries.length, equals(1));

      socket.triggerIncomingEvent('msg', 'hello');
      await pumpEventQueue();

      final frames = engine.getRealtimeFrames(first.scope.sessionId);
      expect(frames.length, equals(1));
    });

    test('connect_error records frame and keeps session open', () async {
      final socket = FakeSocket();
      final tracker = InterceptlySocketIo.attach(
        socket,
        sessionId: 'conn-err-frame-1',
      );

      socket.triggerConnectError('xhr poll error');
      await pumpEventQueue();

      expect(tracker.scope.isClosed, isFalse);
      final frames = engine.getRealtimeFrames(tracker.scope.sessionId);
      expect(frames, isNotEmpty);
      final errorFrames =
          frames.where((f) => f.eventName == 'connect_error').toList();
      expect(errorFrames, isNotEmpty);
      expect(errorFrames.first.textPayload, contains('xhr poll error'));

      socket.triggerIncomingEvent('after:error', 'still live');
      await pumpEventQueue();
      final after = engine.getRealtimeFrames(tracker.scope.sessionId);
      expect(
        after.where((f) => f.eventName == 'after:error'),
        isNotEmpty,
      );
    });

    test('large List<int> binary caps without full copy', () async {
      final normalized = FrameNormalizer.normalize(
        List<int>.filled(5000, 0xAB),
        offloadThreshold: 1024,
        maxBodyBytes: 1024,
      );
      expect(normalized.type, equals(FrameType.binary));
      expect(normalized.originalSizeBytes, equals(5000));
      expect((normalized.payload as Uint8List).length, equals(1024));
      expect(normalized.shouldOffload, isTrue);
      expect(normalized.preEncodedBytes?.length, equals(1024));

      final socket = FakeSocket();
      final tracker = InterceptlySocketIo.attach(
        socket,
        sessionId: 'large-bin-1',
      );

      final largeBytes = Uint8List.fromList(List<int>.filled(2048, 0xAB));
      socket.triggerIncomingEvent('file:chunk', largeBytes);
      await pumpEventQueue();

      final frames = engine.getRealtimeFrames(tracker.scope.sessionId);
      expect(frames.length, equals(1));
      final frame = frames.first;
      expect(frame.type, equals(FrameType.binary));
      expect(frame.binaryPayload, isNotNull);
      expect(frame.payloadSizeBytes, equals(largeBytes.length));
    });

    test('detach is single and stops further capture', () async {
      final socket = FakeSocket();
      final tracker = InterceptlySocketIo.attach(
        socket,
        sessionId: 'detach-single-1',
      );

      socket.triggerIncomingEvent('m1', 'before');
      await pumpEventQueue();
      expect(engine.getRealtimeFrames('detach-single-1').length, equals(1));

      tracker.detach();
      expect(tracker.isDetached, isTrue);

      socket.triggerIncomingEvent('m1', 'after');
      await pumpEventQueue();
      expect(engine.getRealtimeFrames('detach-single-1').length, equals(1));
    });
  });
}
