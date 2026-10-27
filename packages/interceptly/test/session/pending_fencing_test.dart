// ignore_for_file: invalid_use_of_internal_member

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/body_decode_service.dart';
import 'package:interceptly/src/engine/bounded_event_queue.dart';
import 'package:interceptly/src/engine/capture_pipeline.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/model/index_entry.dart';

const _channel = MethodChannel('plugins.flutter.io/path_provider');

/// Polls [condition] until it is true or [timeout] expires.
Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

RawCapture _completion(String id) {
  return RawCapture(
    id: id,
    method: 'GET',
    url: 'https://api.example.com/$id',
    requestHeaders: const {},
    responseHeaders: const {},
    statusCode: 200,
    durationMs: 12,
    timestamp: DateTime(2026),
  );
}

/// Drop-path fencing and late-response gates: dropped captures cancel
///
/// pending timers, late responses after disable never land, and truncation
/// honors the storage cap.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    await Interceptly.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp('pending_fencing_');
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

  group('drop-path fencing', () {
    test('dropped pre-init capture cancels its pending timer', () async {
      final engine = InterceptlyEngine(
        settings: const InterceptlySettings(
          maxQueuedEvents: 2,
          pendingTimeout: Duration(milliseconds: 250),
        ),
      );
      addTearDown(() async {
        try {
          await engine.dispose();
        } catch (_) {}
      });

      engine.recordPending(
        id: 'fenced-pending',
        method: 'GET',
        url: 'https://api.example.com/fenced-pending',
        timestamp: DateTime.now(),
      );

      engine.record(_completion('fenced-pending'));
      engine.record(_completion('other-1'));
      engine.record(_completion('other-2'));
      engine.record(_completion('other-3'));

      await Future<void>.delayed(const Duration(milliseconds: 600));

      final entry = engine.byId('fenced-pending');
      expect(entry, isNotNull);
      expect(entry!.statusCode, 0);
      expect(entry.hasError, isFalse);
      expect(entry.errorType, isNull);
    });

    test('in-flight saturation drop cancels the pending timer', () async {
      final cancelled = <String>[];
      final readyEntries = <IndexEntry>[];
      final pipeline = CapturePipeline(
        settings: const InterceptlySettings(maxQueuedEvents: 1),
        sessionId: 'saturation_fencing',
        onEntryReady: readyEntries.add,
        onEntryReceived: cancelled.add,
      );
      addTearDown(pipeline.dispose);

      await pipeline.initialize();

      pipeline.record(_completion('sat-1'));
      pipeline.record(_completion('sat-2'));
      pipeline.record(_completion('sat-3'));

      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(pipeline.droppedCount, greaterThan(0));
      expect(cancelled, contains('sat-2'));
    });
  });

  group('late-response gates', () {
    test('late response after disable does not land', () async {
      final engine = InterceptlyEngine(
        settings: const InterceptlySettings(
          pendingTimeout: Duration(seconds: 45),
        ),
      );
      addTearDown(() async {
        try {
          await engine.dispose();
        } catch (_) {}
      });
      await engine.initialize();

      engine.recordPending(
        id: 'late-1',
        method: 'GET',
        url: 'https://api.example.com/late-1',
        timestamp: DateTime.now(),
      );
      engine.disable();
      engine.record(_completion('late-1'));

      await Future<void>.delayed(const Duration(seconds: 1));

      final entry = engine.byId('late-1');
      expect(entry, isNotNull);
      expect(entry!.statusCode, 0);
      expect(entry.hasError, isFalse);
    });

    test('authentic late terminal replaces the synthetic timeout', () async {
      final engine = InterceptlyEngine(
        settings: const InterceptlySettings(
          pendingTimeout: Duration(milliseconds: 200),
        ),
      );
      addTearDown(() async {
        try {
          await engine.dispose();
        } catch (_) {}
      });
      await engine.initialize();

      engine.recordPending(
        id: 'timed-out-1',
        method: 'GET',
        url: 'https://api.example.com/timed-out-1',
        timestamp: DateTime.now(),
      );

      await Future<void>.delayed(const Duration(milliseconds: 400));

      var entry = engine.byId('timed-out-1');
      expect(entry, isNotNull);
      expect(entry!.hasError, isTrue);
      expect(entry.errorType, 'TimeoutException');

      engine.record(_completion('timed-out-1'));
      await _waitFor(
        () => engine.byId('timed-out-1')?.statusCode == 200,
      );

      entry = engine.byId('timed-out-1');
      expect(entry, isNotNull);
      expect(entry!.statusCode, equals(200));
      expect(entry.durationMs, equals(12));
      expect(entry.hasError, isFalse);
      expect(entry.errorType, isNull);
      expect(entry.errorMessage, isNull);
    });
  });

  group('bounded queue eviction', () {
    test('add returns the evicted element on overflow', () {
      final queue = BoundedEventQueue<int>(maxSize: 2);
      expect(queue.add(1), isNull);
      expect(queue.add(2), isNull);
      expect(queue.add(3), 1);
      expect(queue.add(4), 2);
      expect(queue.removeFirstOrNull(), 3);
      expect(queue.removeFirstOrNull(), 4);
    });

    test('ignoring the return value stays source-compatible', () {
      final queue = BoundedEventQueue<String>(maxSize: 1);
      queue.add('a');
      queue.add('b');
      expect(queue.length, 1);
      expect(queue.droppedCount, 1);
    });
  });

  group('truncate storage cap', () {
    test('preview never exceeds maxBody', () {
      final bytes = Uint8List(5000);
      final preview = BodyDecodeService.truncate(bytes, 1000, 16 * 1024);
      expect(preview, isNotNull);
      expect(preview!.length, 1000);
    });

    test('smaller preview budget is honored below the cap', () {
      final bytes = Uint8List(5000);
      final preview = BodyDecodeService.truncate(bytes, 4000, 1000);
      expect(preview, isNotNull);
      expect(preview!.length, 1000);
    });

    test('unlimited bodies pass through untouched', () {
      final bytes = Uint8List(5000);
      expect(BodyDecodeService.truncate(bytes, 0, 1000), same(bytes));
    });
  });
}
