// ignore_for_file: invalid_use_of_internal_member
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';
import 'package:interceptly/src/model/raw_capture.dart';
import 'package:interceptly/src/engine/bounded_event_queue.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/engine/memory_index.dart';
import 'package:interceptly/src/ui/detail/detail_search.dart';

const _channel = MethodChannel('plugins.flutter.io/path_provider');

Uint8List _textBytes(int size) {
  final bytes = Uint8List(size);
  bytes.fillRange(0, size, 65);
  return bytes;
}

RawCapture _capture(String id, Uint8List body) {
  return RawCapture(
    id: id,
    method: 'GET',
    url: 'https://api.example.com/$id',
    requestHeaders: const {},
    responseHeaders: const {'content-type': 'application/json'},
    statusCode: 200,
    durationMs: 1,
    timestamp: DateTime(2026),
    responseBodyBytes: RawCapture.wrapBytes(body),
    responseContentType: 'application/json',
  );
}

Future<IndexEntry> _waitForEntry(InterceptlyEngine session, String id) async {
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(end)) {
    for (final entry in session.entries) {
      if (entry.id == id && entry is IndexEntry) return entry;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('entry $id never arrived');
}

IndexEntry _entry(String id) {
  return IndexEntry(
    id: id,
    method: 'GET',
    url: 'https://api.example.com/$id',
    statusCode: 200,
    durationMs: 1,
    requestSizeBytes: 0,
    responseSizeBytes: 0,
    timestamp: DateTime(2026),
    hasError: false,
    requestTruncation: const BodyTruncation.complete(0),
    responseTruncation: const BodyTruncation.complete(0),
    bodyLocation: BodyLocation.memory,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    await Interceptly.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp('settings_propagation_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tempDir.path;
      return null;
    });
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Settings propagation to storage', () {
    test('configure before init applies maxBodyBytes to isolate', () async {
      final session = InterceptlyEngine();
      addTearDown(session.dispose);
      session.configure(const InterceptlySettings(
        maxBodyBytes: 50 * 1024 * 1024,
        maxUiPreviewBytes: 50 * 1024 * 1024,
      ));
      await session.initialize();
      session.record(_capture('big-1', _textBytes(7 * 1024 * 1024)));
      final entry = await _waitForEntry(session, 'big-1');
      expect(entry.responseTruncation.stage, TruncationStage.none);
      final record = await session.loadDetail(entry);
      expect(record.responseTruncation.stage, TruncationStage.none);
      expect(record.responseTruncation.isTruncated, isFalse);
    });

    test('defaults truncate a 7MB body', () async {
      final session = InterceptlyEngine();
      addTearDown(session.dispose);
      await session.initialize();
      session.record(_capture('big-2', _textBytes(7 * 1024 * 1024)));
      final entry = await _waitForEntry(session, 'big-2');
      expect(entry.responseTruncation.stage, TruncationStage.storage);
      expect(entry.responseTruncation.hasDataLoss, isTrue);
      expect(entry.responseTruncation.originalBytes, 7 * 1024 * 1024);
      expect(entry.responseTruncation.retainedBytes, 5 * 1024 * 1024);
    });

    test('configure after init updates running isolate', () async {
      final session = InterceptlyEngine();
      addTearDown(session.dispose);
      await session.initialize();
      session.configure(const InterceptlySettings(maxBodyBytes: 1024));
      session.record(_capture('small-1', _textBytes(4 * 1024)));
      final entry = await _waitForEntry(session, 'small-1');
      expect(entry.responseTruncation.stage, TruncationStage.storage);
      session.configure(const InterceptlySettings(
        maxBodyBytes: 50 * 1024 * 1024,
        maxUiPreviewBytes: 50 * 1024 * 1024,
      ));
      session.record(_capture('big-3', _textBytes(7 * 1024 * 1024)));
      final big = await _waitForEntry(session, 'big-3');
      expect(big.responseTruncation.stage, TruncationStage.none);
    });

    test('closure shouldCapture does not break isolate spawn', () async {
      final session = InterceptlyEngine();
      addTearDown(session.dispose);
      session.configure(InterceptlySettings(
        shouldCapture: (url) => !url.contains('skip'),
      ));
      await session.initialize();
      session.record(_capture('ok-1', _textBytes(16)));
      final entry = await _waitForEntry(session, 'ok-1');
      expect(entry.responseTruncation.isTruncated, isFalse);
    });
  });

  group('Settings propagation to memory structures', () {
    test('updateMaxEntries shrinks keeping newest', () {
      final index = MemoryIndex(maxEntries: 5);
      for (var i = 0; i < 5; i++) {
        index.add(_entry('e$i'));
      }
      index.updateMaxEntries(2);
      expect(index.length, equals(2));
      expect(index.entries.map((e) => e.id).toList(), equals(['e4', 'e3']));
      index.add(_entry('e5'));
      expect(index.entries.map((e) => e.id).toList(), equals(['e5', 'e4']));
    });

    test('updateMaxEntries grows keeping all', () {
      final index = MemoryIndex(maxEntries: 2);
      index.add(_entry('a'));
      index.add(_entry('b'));
      index.updateMaxEntries(5);
      index.add(_entry('c'));
      expect(index.entries.map((e) => e.id).toList(), equals(['c', 'b', 'a']));
    });

    test('updateMaxSize trims queued overflow', () {
      final queue = BoundedEventQueue<int>(maxSize: 5);
      for (var i = 0; i < 5; i++) {
        queue.add(i);
      }
      queue.updateMaxSize(2);
      expect(queue.length, equals(2));
      expect(queue.droppedCount, equals(3));
      queue.add(99);
      expect(queue.length, equals(2));
    });
  });

  group('Truncation reporting per stage', () {
    test('body under both caps reports no truncation', () async {
      final session = InterceptlyEngine();
      addTearDown(session.dispose);
      await session.initialize();
      session.record(_capture('clean', _textBytes(512 * 1024)));
      final entry = await _waitForEntry(session, 'clean');
      final record = await session.loadDetail(entry);
      expect(record.responseTruncation.stage, TruncationStage.none);
      expect(record.responseTruncation.isTruncated, isFalse);
    });

    test('maxUi below maxBody reports preview-only, keeps full bytes',
        () async {
      final session = InterceptlyEngine();
      addTearDown(session.dispose);
      session.configure(const InterceptlySettings(
        maxBodyBytes: 50 * 1024 * 1024,
        maxUiPreviewBytes: 2 * 1024 * 1024,
      ));
      await session.initialize();
      session.record(_capture('ui-cut', _textBytes(7 * 1024 * 1024)));
      final entry = await _waitForEntry(session, 'ui-cut');
      final record = await session.loadDetail(entry);
      expect(record.responseTruncation.stage, TruncationStage.preview);
      expect(record.responseTruncation.hasDataLoss, isFalse);
      expect(record.responseTruncation.isPreviewOnly, isTrue);
      expect(record.responseTruncation.originalBytes, 7 * 1024 * 1024);
      expect(record.responseTruncation.retainedBytes, 2 * 1024 * 1024);
      expect(record.responseBodyBytes, isNotNull);
      expect(
        record.responseBodyBytes!.length,
        7 * 1024 * 1024,
        reason: 'storage must still hold every byte',
      );
    });

    test('body over both caps reports storageAndPreview', () async {
      final session = InterceptlyEngine();
      addTearDown(session.dispose);
      session.configure(const InterceptlySettings(
        maxBodyBytes: 5 * 1024 * 1024,
        maxUiPreviewBytes: 1024 * 1024,
      ));
      await session.initialize();
      session.record(_capture('both-cut', _textBytes(7 * 1024 * 1024)));
      final entry = await _waitForEntry(session, 'both-cut');
      final record = await session.loadDetail(entry);
      expect(
          record.responseTruncation.stage, TruncationStage.storageAndPreview);
      expect(record.responseTruncation.hasDataLoss, isTrue);
      expect(record.responseTruncation.retainedBytes, 1024 * 1024);
    });

    test('notice text reflects stage and shared with search matcher', () {
      expect(
        bodyTruncationNotices(const BodyTruncation.complete(10)),
        isEmpty,
      );
      expect(
        bodyTruncationNotices(const BodyTruncation(
          originalBytes: 7000000,
          retainedBytes: 2000000,
          stage: TruncationStage.preview,
        )),
        [
          'Showing the first 1.91 MB of 6.68 MB here. Nothing is lost — '
              'exports and replay still carry the full body.'
        ],
      );
      final storageOnly = bodyTruncationNotices(const BodyTruncation(
        originalBytes: 7000000,
        retainedBytes: 5000000,
        stage: TruncationStage.storage,
      ));
      expect(storageOnly.single, contains('maxBodyBytes'));
      expect(storageOnly.single, contains('discarded'));
    });

    test('request and response truncation are tracked independently', () async {
      final session = InterceptlyEngine();
      addTearDown(session.dispose);
      session.configure(const InterceptlySettings(
        maxBodyBytes: 1024,
        maxUiPreviewBytes: 50 * 1024 * 1024,
      ));
      await session.initialize();
      session.record(RawCapture(
        id: 'mixed',
        method: 'POST',
        url: 'https://api.example.com/mixed',
        requestHeaders: const {},
        responseHeaders: const {},
        statusCode: 200,
        durationMs: 1,
        timestamp: DateTime(2026),
        requestBodyBytes: RawCapture.wrapBytes(_textBytes(4096)),
        responseBodyBytes: RawCapture.wrapBytes(_textBytes(16)),
      ));
      final entry = await _waitForEntry(session, 'mixed');
      expect(entry.requestTruncation.stage, TruncationStage.storage);
      expect(entry.responseTruncation.stage, TruncationStage.none);
      expect(entry.hasDataLoss, isTrue);
      expect(entry.isTruncated, isTrue);
    });
  });
}
