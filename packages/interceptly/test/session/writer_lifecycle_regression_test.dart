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

RawCapture _capture(String id) {
  return RawCapture(
    id: id,
    method: 'GET',
    url: 'https://api.example.com/$id',
    requestHeaders: const {},
    responseHeaders: const {},
    statusCode: 200,
    durationMs: 1,
    timestamp: DateTime(2026),
  );
}

/// Writer isolate lifecycle: concurrent clear, restart drops, sticky init,
///
/// and dispose idempotence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    await Interceptly.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp('writer_lifecycle_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tempDir.path;
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } catch (_) {}
    await Interceptly.resetForTesting();
  });

  group('WriterIsolate lifecycle', () {
    test('concurrent clear calls both complete', () async {
      final writer = WriterIsolate(const InterceptlySettings());
      addTearDown(writer.dispose);

      await writer.start(
        tempDirPath: tempDir.path,
        fileName: 'concurrent_clear.tmp',
      );
      writer.send(_capture('clear-1'));

      await Future.wait([
        writer.clear().timeout(const Duration(seconds: 10)),
        writer.clear().timeout(const Duration(seconds: 10)),
      ]);
    });

    test('restart overflow drops are counted', () async {
      final writer = WriterIsolate(
        const InterceptlySettings(maxQueuedEvents: 2),
      );
      addTearDown(writer.dispose);

      await writer.start(
        tempDirPath: tempDir.path,
        fileName: 'restart_drops.tmp',
      );

      final restarting = writer.restart(
        tempDirPath: tempDir.path,
        fileName: 'restart_drops.tmp',
      );
      for (var i = 0; i < 5; i++) {
        writer.send(_capture('restart-$i'));
      }
      await restarting.timeout(const Duration(seconds: 15));

      expect(writer.restartDroppedCount, greaterThan(0));
    });

    test('dispose is idempotent', () async {
      final writer = WriterIsolate(const InterceptlySettings());
      await writer.start(
        tempDirPath: tempDir.path,
        fileName: 'dispose_idempotent.tmp',
      );

      await writer.dispose();
      await writer.dispose();
    });
  });

  group('CapturePipeline sticky init', () {
    test('failed init retries on next initialize', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        throw PlatformException(code: 'IO_ERROR', message: 'disk failure');
      });

      final readyEntries = <IndexEntry>[];
      final pipeline = CapturePipeline(
        settings: const InterceptlySettings(),
        sessionId: 'sticky_init',
        onEntryReady: readyEntries.add,
      );
      addTearDown(pipeline.dispose);

      await pipeline.initialize();
      expect(pipeline.isDegraded, isTrue);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      });

      await pipeline.initialize();
      expect(pipeline.isInitialized, isTrue);
      expect(pipeline.isDegraded, isFalse);
    });

    test('pipeline droppedCount folds writer restart drops', () async {
      final readyEntries = <IndexEntry>[];
      final pipeline = CapturePipeline(
        settings: const InterceptlySettings(maxQueuedEvents: 2),
        sessionId: 'restart_fold',
        onEntryReady: readyEntries.add,
      );
      addTearDown(pipeline.dispose);

      await pipeline.initialize();

      final writer = pipeline.writerIsolate;
      final restarting = writer.restart(
        tempDirPath: tempDir.path,
        fileName: 'interceptly_restart_fold_session.tmp',
      );
      for (var i = 0; i < 5; i++) {
        writer.send(_capture('fold-$i'));
      }
      await restarting.timeout(const Duration(seconds: 15));

      expect(pipeline.droppedCount, greaterThan(0));
    });

    test('dispose during initialize does not throw', () async {
      final readyEntries = <IndexEntry>[];
      final pipeline = CapturePipeline(
        settings: const InterceptlySettings(),
        sessionId: 'dispose_during_init',
        onEntryReady: readyEntries.add,
      );

      final initializing = pipeline.initialize();
      await pipeline.dispose();
      await initializing;

      expect(pipeline.isDisposed, isTrue);
    });
  });

  group('engine init recovery', () {
    test('engine initializes after a transient init failure', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        throw PlatformException(code: 'IO_ERROR', message: 'disk failure');
      });

      final engine = InterceptlyEngine();
      addTearDown(() async {
        try {
          await engine.dispose();
        } catch (_) {}
      });

      await engine.initialize();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      });

      await engine.initialize();
    });
  });
}
