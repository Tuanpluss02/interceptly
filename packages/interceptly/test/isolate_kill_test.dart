import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';
import 'package:interceptly/src/model/raw_capture.dart';
import 'package:interceptly/src/session/capture_pipeline.dart';
import 'package:interceptly/src/session/inspector_session.dart';
import 'package:interceptly/src/session/writer_isolate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('isolate_kill_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getTemporaryDirectory') {
        return tempDir.path;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  RawCapture createCapture({
    String id = 'cap-1',
    int bodySize = 100,
    String? errorType,
  }) {
    final bodyBytes = Uint8List.fromList(List.filled(bodySize, 65));
    return RawCapture(
      id: id,
      method: 'POST',
      url: 'https://api.example.com/test',
      statusCode: 200,
      durationMs: 40,
      timestamp: DateTime.now(),
      requestHeaders: const {},
      responseHeaders: const {},
      errorType: errorType,
      requestBodyBytes: RawCapture.wrapBytes(bodyBytes),
      responseBodyBytes: RawCapture.wrapBytes(bodyBytes),
      requestContentType: 'text/plain',
      responseContentType: 'text/plain',
    );
  }

  group('WriterIsolate Lifecycle and Cleanup Fallback', () {
    test('cleans up temp file on disk even after immediate termination', () async {
      final writer = WriterIsolate(const InterceptlySettings());
      await writer.start(
        tempDirPath: tempDir.path,
        fileName: 'isolate_kill_file.tmp',
      );

      final filePath = '${tempDir.path}/isolate_kill_file.tmp';
      final file = File(filePath);

      writer.send(createCapture(id: 'c1', bodySize: 200));

      final entry = await writer.results.first;
      expect(entry.id, equals('c1'));
      expect(await file.exists(), isTrue);

      await writer.dispose();

      expect(await file.exists(), isFalse);
    });

    test('stream closes gracefully when writer isolate is disposed', () async {
      final writer = WriterIsolate(const InterceptlySettings());
      await writer.start(
        tempDirPath: tempDir.path,
        fileName: 'isolate_stream_close.tmp',
      );

      var isStreamDone = false;
      writer.results.listen(
        (_) {},
        onDone: () => isStreamDone = true,
      );

      await writer.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(isStreamDone, isTrue);
    });
  });

  group('CapturePipeline DroppedCount and Error Accounting', () {
    test('pipeline increments droppedCount when saturated beyond maxQueuedEvents', () async {
      const maxQueue = 3;
      final readyEntries = <IndexEntry>[];

      final pipeline = CapturePipeline(
        settings: const InterceptlySettings(maxQueuedEvents: maxQueue),
        sessionId: 'test_queue_sat',
        onEntryReady: readyEntries.add,
      );

      for (var i = 0; i < 10; i++) {
        pipeline.record(createCapture(id: 'pre-$i'));
      }

      expect(pipeline.droppedCount, greaterThan(0));

      await pipeline.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await pipeline.dispose();
    });

    test('pipeline dispose clears in-flight tracking and cleans resources', () async {
      final readyEntries = <IndexEntry>[];
      final pipeline = CapturePipeline(
        settings: const InterceptlySettings(),
        sessionId: 'test_pipeline_disp',
        onEntryReady: readyEntries.add,
      );

      await pipeline.initialize();
      expect(pipeline.isInitialized, isTrue);

      pipeline.record(createCapture(id: 'disp-1'));

      await pipeline.dispose();
      expect(pipeline.isInitialized, isFalse);
      expect(pipeline.inFlight, equals(0));
    });
  });

  group('Large Payload Storage Cap and hasDataLoss Invariant', () {
    test('recording payload exceeding maxBodyBytes sets hasDataLoss = true', () async {
      final session = InspectorSession(
        settings: const InterceptlySettings(
          maxBodyBytes: 1024,
          bodyOffloadThreshold: 256,
        ),
      );
      addTearDown(session.dispose);
      await session.initialize();

      final largeBody = Uint8List(4096);
      session.record(
        RawCapture(
          id: 'large-cap-1',
          method: 'POST',
          url: 'https://api.example.com/upload',
          statusCode: 200,
          durationMs: 50,
          timestamp: DateTime.now(),
          requestHeaders: const {},
          responseHeaders: const {},
          requestBodyBytes: RawCapture.wrapBytes(largeBody),
          responseBodyBytes: RawCapture.wrapBytes(largeBody),
        ),
      );

      final end = DateTime.now().add(const Duration(seconds: 4));
      while (session.entries.isEmpty && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(session.entries.isNotEmpty, isTrue);
      final summary = session.entries.first;
      expect(summary.id, equals('large-cap-1'));

      final record = await session.loadDetail(summary);

      expect(record.requestTruncation.hasDataLoss, isTrue);
      expect(record.requestTruncation.stage, equals(TruncationStage.storage));
      expect(record.requestTruncation.originalBytes, equals(4096));
      expect(record.requestTruncation.retainedBytes, lessThanOrEqualTo(1024));

      expect(record.responseTruncation.hasDataLoss, isTrue);
      expect(record.responseTruncation.stage, equals(TruncationStage.storage));
    });
  });
}
