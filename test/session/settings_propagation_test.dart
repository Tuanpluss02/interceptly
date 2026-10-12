import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';
import 'package:interceptly/src/model/raw_capture.dart';
import 'package:interceptly/src/session/bounded_event_queue.dart';
import 'package:interceptly/src/session/inspector_session.dart';
import 'package:interceptly/src/session/memory_index.dart';

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

Future<IndexEntry> _waitForEntry(InspectorSession session, String id) async {
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
    isBodyTruncated: false,
    bodyLocation: BodyLocation.memory,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('settings_propagation_');
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

  group('Settings propagation to storage', () {
    test('configureSession before init applies maxBodyBytes to isolate',
        () async {
      final session = InspectorSession();
      addTearDown(session.dispose);
      session.configureSession(const InterceptlySettings(
        maxBodyBytes: 50 * 1024 * 1024,
        maxUiPreviewBytes: 50 * 1024 * 1024,
      ));
      await session.initialize();
      session.record(_capture('big-1', _textBytes(7 * 1024 * 1024)));
      final entry = await _waitForEntry(session, 'big-1');
      expect(entry.isBodyTruncated, isFalse);
      final record = await session.loadDetail(entry);
      expect(record.isBodyTruncated, isFalse);
      expect(record.isUiTruncated, isFalse);
    });

    test('defaults truncate a 7MB body', () async {
      final session = InspectorSession();
      addTearDown(session.dispose);
      await session.initialize();
      session.record(_capture('big-2', _textBytes(7 * 1024 * 1024)));
      final entry = await _waitForEntry(session, 'big-2');
      expect(entry.isBodyTruncated, isTrue);
    });

    test('configureSession after init updates running isolate', () async {
      final session = InspectorSession();
      addTearDown(session.dispose);
      await session.initialize();
      session.configureSession(const InterceptlySettings(maxBodyBytes: 1024));
      session.record(_capture('small-1', _textBytes(4 * 1024)));
      final entry = await _waitForEntry(session, 'small-1');
      expect(entry.isBodyTruncated, isTrue);
      session.configureSession(const InterceptlySettings(
        maxBodyBytes: 50 * 1024 * 1024,
        maxUiPreviewBytes: 50 * 1024 * 1024,
      ));
      session.record(_capture('big-3', _textBytes(7 * 1024 * 1024)));
      final big = await _waitForEntry(session, 'big-3');
      expect(big.isBodyTruncated, isFalse);
    });

    test('closure shouldCapture does not break isolate spawn', () async {
      final session = InspectorSession();
      addTearDown(session.dispose);
      session.configureSession(InterceptlySettings(
        shouldCapture: (url) => !url.contains('skip'),
      ));
      await session.initialize();
      session.record(_capture('ok-1', _textBytes(16)));
      final entry = await _waitForEntry(session, 'ok-1');
      expect(entry.isBodyTruncated, isFalse);
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
}
