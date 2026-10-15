import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';
import 'package:interceptly/src/model/raw_capture.dart';
import 'package:interceptly/src/session/inspector_session.dart';

const _channel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backpressure_bytes_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'getTemporaryDirectory') {
        return tempDir.path;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  RawCapture createLargeCapture({
    required String id,
    required int byteSize,
  }) {
    return RawCapture(
      id: id,
      method: 'POST',
      url: 'https://api.example.com/large/$id',
      statusCode: 200,
      durationMs: 50,
      timestamp: DateTime.now(),
      requestHeaders: const {},
      responseHeaders: const {},
      requestSizeBytes: byteSize,
      responseSizeBytes: 0,
    );
  }

  group('Dual Backpressure (inFlightBytes)', () {
    test('dual backpressure drops capture when inFlightBytes exceeds 32MB',
        () async {
      final session = InspectorSession(
        settings: const InterceptlySettings(
          maxQueuedEvents: 1000,
        ),
      );
      addTearDown(session.dispose);
      await session.initialize();

      // maxInFlightBytes is 32MB (33,554,432 bytes)
      // Send two 20MB captures (40MB total) -> exceeds 32MB
      const twentyMb = 20 * 1024 * 1024;
      session.record(createLargeCapture(id: 'large-1', byteSize: twentyMb));
      session.record(createLargeCapture(id: 'large-2', byteSize: twentyMb));

      // 3rd capture should be dropped immediately due to inFlightBytes >= 32MB
      session.record(createLargeCapture(id: 'large-3', byteSize: 1024));

      expect(session.droppedCount, greaterThanOrEqualTo(1),
          reason: 'large-3 must be dropped because inFlightBytes exceeds 32MB');
    });

    test('inFlightBytes drains and allows subsequent captures after completion',
        () async {
      final session = InspectorSession();
      addTearDown(session.dispose);
      await session.initialize();

      const thirtyMb = 30 * 1024 * 1024;
      session.record(createLargeCapture(id: 'first-big', byteSize: thirtyMb));

      // Wait for first-big to complete processing
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (session.capturePipeline.inFlightBytes > 0 &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(session.capturePipeline.inFlightBytes, equals(0));

      // Now sending another capture should not be dropped
      final initialDropped = session.droppedCount;
      session.record(createLargeCapture(id: 'second-cap', byteSize: 1024));

      expect(session.droppedCount, equals(initialDropped));
    });
  });
}
