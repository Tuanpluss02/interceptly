import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/raw_capture.dart';
import 'package:interceptly/src/session/bounded_event_queue.dart';
import 'package:interceptly/src/session/inspector_session.dart';
import 'package:interceptly/src/session/memory_index.dart';
import 'package:interceptly/src/session/ring_buffer.dart';

const _channel = MethodChannel('plugins.flutter.io/path_provider');

Uint8List _filledBytes(int size, int byte) {
  final bytes = Uint8List(size);
  bytes.fillRange(0, size, byte);
  return bytes;
}

RawCapture _capture(String id, {Uint8List? body}) {
  return RawCapture(
    id: id,
    method: 'GET',
    url: 'https://api.example.com/$id',
    requestHeaders: const {},
    responseHeaders: const {'content-type': 'application/octet-stream'},
    statusCode: 200,
    durationMs: 1,
    timestamp: DateTime(2026),
    responseBodyBytes: RawCapture.wrapBytes(body),
    responseContentType: 'application/octet-stream',
  );
}

Future<bool> _waitForId(InspectorSession session, String id) async {
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(end)) {
    for (final entry in session.entries) {
      if (entry.id == id) return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return false;
}

IndexEntry _memoryEntry(String id) {
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
    tempDir = await Directory.systemTemp.createTemp('clear_generation_');
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
  });

  group('clear generation fence', () {
    test('records racing mid-clear do not resurrect after clear', () async {
      final session = InspectorSession();
      addTearDown(session.dispose);
      await session.initialize();
      for (var i = 0; i < 100; i++) {
        session.record(_capture('burst-$i'));
      }
      final clearing = session.clear();
      for (var i = 100; i < 120; i++) {
        session.record(_capture('burst-$i'));
      }
      await clearing;
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(session.entries, isEmpty);
      expect(session.totalEntries, 0);
    });

    test('entries recorded after clear do not alias pre-clear file offsets',
        () async {
      final session = InspectorSession();
      addTearDown(session.dispose);
      await session.initialize();
      session.record(
        _capture('pre-clear', body: _filledBytes(60 * 1024, 65)),
      );
      final clearing = session.clear();
      session.record(
        _capture('mid-clear', body: _filledBytes(60 * 1024, 66)),
      );
      await clearing;
      session.record(
        _capture('post-clear', body: _filledBytes(60 * 1024, 67)),
      );
      expect(await _waitForId(session, 'post-clear'), isTrue);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(session.entries.map((e) => e.id).toList(), ['post-clear']);
      final entry = session.entries.singleWhere((e) => e.id == 'post-clear');
      final record = await session.loadDetail(entry);
      expect(record.responseBodyBytes, isNotNull);
      expect(record.responseBodyBytes!.length, 60 * 1024);
      expect(
        record.responseBodyBytes!.every((b) => b == 67),
        isTrue,
        reason: 'post-clear body must not read pre-clear bytes at offset 0',
      );
    });

    test(
        'DetailLoader marks body as unavailable when entry fileRotationCount is older than current rotation',
        () async {
      final session = InspectorSession();
      addTearDown(session.dispose);
      await session.initialize();

      // Create an index entry that points to an older fileRotationCount
      final staleEntry = IndexEntry(
        id: 'stale-rot',
        method: 'GET',
        url: 'https://api.example.com/stale',
        statusCode: 200,
        durationMs: 10,
        requestSizeBytes: 0,
        responseSizeBytes: 500,
        timestamp: DateTime(2026),
        hasError: false,
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation.complete(500),
        bodyLocation: BodyLocation.file,
        fileOffset: 0,
        fileLength: 500,
        fileRotationCount: 0,
      );

      // Trigger pipeline clear/reset which increments rotation
      await session.clear();

      final record = await session.loadDetail(staleEntry);
      expect(record.responseBodyPreview, equals('\x00[body unavailable]'));
      expect(record.responseBodyBytes, isNull);
    });
  });

  group('capacity clamps', () {
    test('MemoryIndex clamps maxEntries 0 instead of throwing', () {
      final index = MemoryIndex(maxEntries: 0);
      index.add(_memoryEntry('a'));
      index.add(_memoryEntry('b'));
      expect(index.length, 1);
      expect(index.entries.single.id, 'b');
    });

    test('MemoryIndex.updateMaxEntries clamps 0 instead of throwing', () {
      final index = MemoryIndex(maxEntries: 2);
      index.add(_memoryEntry('a'));
      index.updateMaxEntries(0);
      index.add(_memoryEntry('b'));
      expect(index.length, 1);
    });

    test('RingBuffer clamps capacity 0 instead of throwing', () {
      final buffer = RingBuffer<int>(capacity: 0);
      buffer.add(1);
      buffer.add(2);
      expect(buffer.length, 1);
      expect(buffer.toList(), [2]);
    });

    test('RingBuffer.updateCapacity clamps 0 instead of throwing', () {
      final buffer = RingBuffer<int>(capacity: 2);
      buffer.add(1);
      buffer.updateCapacity(0);
      buffer.add(2);
      expect(buffer.length, 1);
    });

    test('BoundedEventQueue clamps maxSize 0 instead of throwing', () {
      final queue = BoundedEventQueue<int>(maxSize: 0);
      queue.add(1);
      queue.add(2);
      expect(queue.length, 1);
      expect(queue.removeFirstOrNull(), 2);
    });

    test('BoundedEventQueue.updateMaxSize clamps 0 instead of throwing', () {
      final queue = BoundedEventQueue<int>(maxSize: 2);
      queue.add(1);
      queue.updateMaxSize(0);
      queue.add(2);
      expect(queue.length, 1);
    });

    test('MemoryIndex with maxEntries 0 still records', () {
      final index = MemoryIndex(maxEntries: 0);
      index.add(_memoryEntry('clamped-1'));
      expect(index.length, 1);
      expect(index.entries.single.id, 'clamped-1');
    });
  });
}
