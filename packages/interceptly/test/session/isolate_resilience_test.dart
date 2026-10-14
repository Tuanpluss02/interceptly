import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/raw_capture.dart';
import 'package:interceptly/src/session/inspector_session.dart';

const _channel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('isolate_resilience_test_');
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

  RawCapture createCapture({
    required String id,
    int bodySize = 100,
    int? requestSizeBytes,
    int? responseSizeBytes,
  }) {
    final bodyBytes = Uint8List(bodySize);
    return RawCapture(
      id: id,
      method: 'POST',
      url: 'https://api.example.com/test/$id',
      statusCode: 200,
      durationMs: 20,
      timestamp: DateTime.now(),
      requestHeaders: const {},
      responseHeaders: const {},
      requestBodyBytes: RawCapture.wrapBytes(bodyBytes),
      responseBodyBytes: RawCapture.wrapBytes(bodyBytes),
      requestSizeBytes: requestSizeBytes ?? bodySize,
      responseSizeBytes: responseSizeBytes ?? bodySize,
      requestContentType: 'application/octet-stream',
      responseContentType: 'application/octet-stream',
    );
  }

  Future<bool> waitForEntry(
    InspectorSession session,
    String id, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      for (final entry in session.entries) {
        if (entry.id == id) return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return false;
  }

  group('Isolate Resilience & Lifecycle Guards', () {
    test('enable after dispose does not revive session', () {
      final session = InspectorSession();
      session.dispose();
      session.enable();
      expect(session.isEnabled, isFalse);
    });

    test(
      'isolate death resets inFlight and allows subsequent captures via fallback or respawn',
      () async {
        final session = InspectorSession();
        addTearDown(session.dispose);
        await session.initialize();

        // Send first capture and verify processed
        session.record(createCapture(id: 'cap-before'));
        expect(await waitForEntry(session, 'cap-before'), isTrue);

        // Kill the isolate forcibly
        final isolate = session.writerIsolate.rawIsolate;
        expect(isolate, isNotNull);
        isolate!.kill(priority: Isolate.immediate);

        // Allow watchdog to detect exit and handle respawn/reset
        await Future<void>.delayed(const Duration(milliseconds: 150));

        // Record subsequent captures
        session.record(createCapture(id: 'cap-after-1'));
        session.record(createCapture(id: 'cap-after-2'));

        // Verify captures are not dropped silently due to stuck inFlight
        expect(
          await waitForEntry(session, 'cap-after-1'),
          isTrue,
          reason: 'cap-after-1 must be processed and not dropped',
        );
        expect(
          await waitForEntry(session, 'cap-after-2'),
          isTrue,
          reason: 'cap-after-2 must be processed and not dropped',
        );
        expect(session.capturePipeline.inFlight, equals(0));
      },
    );

    test(
      'circuit breaker enters degraded fallback mode and halts retry storm on init error',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, (call) async {
          throw PlatformException(code: 'IO_ERROR', message: 'Disk failure');
        });

        final session = InspectorSession();
        addTearDown(session.dispose);

        await session.initialize();

        expect(session.capturePipeline.isDegraded, isTrue);

        // Subsequent records should succeed in-memory without retry storm
        session.record(createCapture(id: 'fallback-1'));
        session.record(createCapture(id: 'fallback-2'));

        expect(await waitForEntry(session, 'fallback-1'), isTrue);
        expect(await waitForEntry(session, 'fallback-2'), isTrue);
        expect(session.droppedCount, equals(0));
      },
    );

    test(
      'watchdog falls back to in-memory mode after exceeding 3 respawn attempts',
      () async {
        final session = InspectorSession();
        addTearDown(session.dispose);
        await session.initialize();

        // Kill isolate 4 times to exceed 3 respawns
        for (var i = 0; i < 4; i++) {
          final iso = session.writerIsolate.rawIsolate;
          if (iso != null) {
            iso.kill(priority: Isolate.immediate);
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

        expect(session.capturePipeline.isDegraded, isTrue);

        // Capture in degraded mode
        session.record(createCapture(id: 'after-4th-kill'));
        expect(await waitForEntry(session, 'after-4th-kill'), isTrue);
        expect(session.droppedCount, equals(0));
      },
    );
  });
}
