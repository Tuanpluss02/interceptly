// ignore_for_file: invalid_use_of_internal_member

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/capture_pipeline.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/engine/writer_isolate.dart';
import 'package:interceptly/src/model/index_entry.dart';

const _channel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    await Interceptly.resetForTesting();
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
    await Interceptly.resetForTesting();
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

  group('Isolate Resilience & Lifecycle Guards', () {
    test('enable after dispose does not revive session', () async {
      final engine = InterceptlyEngine();
      await engine.dispose();
      engine.enable();
      expect(engine.isEnabled, isFalse);
    });

    test(
      'circuit breaker enters degraded fallback mode and halts retry storm on init error',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, (call) async {
          throw PlatformException(code: 'IO_ERROR', message: 'Disk failure');
        });

        final readyEntries = <IndexEntry>[];
        final pipeline = CapturePipeline(
          settings: const InterceptlySettings(),
          sessionId: 'test_circuit_breaker',
          onEntryReady: readyEntries.add,
        );
        addTearDown(pipeline.dispose);

        await pipeline.initialize();

        expect(pipeline.isDegraded, isTrue);

        pipeline.record(createCapture(id: 'fallback-1'));
        pipeline.record(createCapture(id: 'fallback-2'));

        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(readyEntries.any((e) => e.id == 'fallback-1'), isTrue);
        expect(readyEntries.any((e) => e.id == 'fallback-2'), isTrue);
        expect(pipeline.droppedCount, equals(0));
      },
    );

    test('WriterIsolate restart cleans up and restarts isolate gracefully',
        () async {
      final writer = WriterIsolate(const InterceptlySettings());
      addTearDown(writer.dispose);

      await writer.start(
        tempDirPath: tempDir.path,
        fileName: 'isolate_restart_test.tmp',
      );
      expect(writer.isReady, isTrue);

      writer.send(createCapture(id: 'before_restart'));
      final entry1 = await writer.results.first;
      expect(entry1.id, equals('before_restart'));

      await writer.restart(
        tempDirPath: tempDir.path,
        fileName: 'isolate_restart_test.tmp',
      );
      expect(writer.isReady, isTrue);

      writer.send(createCapture(id: 'after_restart'));
      final entry2 = await writer.results.first;
      expect(entry2.id, equals('after_restart'));
    });

    test(
      'CapturePipeline in degraded fallback mode processes subsequent captures in-memory and sets memory location',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, (call) async {
          throw PlatformException(
              code: 'NOT_FOUND', message: 'Temp path failure');
        });

        final readyEntries = <IndexEntry>[];
        final pipeline = CapturePipeline(
          settings: const InterceptlySettings(),
          sessionId: 'test_fallback_mode',
          onEntryReady: readyEntries.add,
        );
        addTearDown(pipeline.dispose);

        await pipeline.initialize();
        expect(pipeline.isDegraded, isTrue);

        pipeline.record(createCapture(id: 'in-memory-1', bodySize: 200));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(readyEntries.length, equals(1));
        final entry = readyEntries.first;
        expect(entry.id, equals('in-memory-1'));
        expect(entry.bodyLocation, equals(BodyLocation.memory));
        expect(pipeline.droppedCount, equals(0));
      },
    );
  });
}
