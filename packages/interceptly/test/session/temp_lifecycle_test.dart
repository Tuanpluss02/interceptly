import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';
import 'package:interceptly/src/model/raw_capture.dart';
import 'package:interceptly/src/session/body_store.dart';
import 'package:interceptly/src/session/inspector_session.dart';
import 'package:interceptly/src/session/writer_isolate.dart';

const _channel = MethodChannel('plugins.flutter.io/path_provider');

Uint8List _bytes(int size, int fill) {
  final bytes = Uint8List(size);
  bytes.fillRange(0, size, fill);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('temp_lifecycle_');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('temp file lifecycle (RED)', () {
    test('WriterIsolate.dispose while busy still deletes the temp file',
        () async {
      final writer = WriterIsolate(const InterceptlySettings(
        bodyOffloadThreshold: 1,
        maxBodyBytes: 0,
      ));
      await writer.start(
        tempDirPath: tempDir.path,
        fileName: 'interceptly_busy_session.tmp',
      );
      final file = File('${tempDir.path}/interceptly_busy_session.tmp');
      final readyDeadline = DateTime.now().add(const Duration(seconds: 10));
      while (!file.existsSync() && DateTime.now().isBefore(readyDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await file.exists(), isTrue);

      for (var i = 0; i < 300; i++) {
        writer.send(_capture('busy-$i', body: _bytes(256 * 1024, i % 256)));
      }
      await writer.dispose();

      expect(await file.exists(), isFalse,
          reason: 'busy dispose must not leak the temp file');
    });

    test("live session B survives session A's init purge", () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      });

      final stale = File('${tempDir.path}/interceptly_stale_crash.tmp');
      await stale.writeAsString('stale crash payload');
      await stale.setLastModified(
          DateTime.now().subtract(const Duration(hours: 25)));

      final sessionA = InspectorSession();
      await sessionA.initialize();
      final fileA = tempDir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.uri.pathSegments.last.startsWith('interceptly_') &&
              f.uri.pathSegments.last.endsWith('.tmp'))
          .toList();
      expect(fileA.length, equals(1));

      final sessionB = InspectorSession();
      await sessionB.initialize();

      expect(await fileA.single.exists(), isTrue,
          reason: "B's init purge must spare live A's fresh file");
      expect(await stale.exists(), isFalse,
          reason: 'stale orphans older than 24h are still purged');

      await sessionA.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await fileA.single.exists(), isFalse);
      final remaining = tempDir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.uri.pathSegments.last.startsWith('interceptly_') &&
              f.uri.pathSegments.last.endsWith('.tmp'))
          .toList();
      expect(remaining.length, equals(1),
          reason: "disposing A must not delete live B's file");

      await sessionB.dispose();
    });

    test('BodyStore rotates single file when exceeding disk cap', () async {
      expect(BodyStore.kMaxFileBytes, equals(100 * 1024 * 1024));

      final store = BodyStore(maxFileBytes: 1024);
      await store.initForWrite(tempDir.path, fileName: 'rotate_test.tmp');

      final (offset1, len1) = await store.append(_bytes(600, 1));
      expect(offset1, equals(0));
      expect(len1, equals(600));
      expect(store.currentOffset, equals(600));
      expect(store.rotationCount, equals(0));

      final (offset2, len2) = await store.append(_bytes(500, 2));
      expect(offset2, equals(0),
          reason: 'exceeding 1024 bytes must rotate and reset offset to 0');
      expect(len2, equals(500));
      expect(store.currentOffset, equals(500));
      expect(store.rotationCount, equals(1));

      await store.dispose();
    });

    test('WriterIsolate with persistToDisk: false keeps bodies in memory',
        () async {
      final writer = WriterIsolate(const InterceptlySettings(
        bodyOffloadThreshold: 10,
        maxBodyBytes: 0,
        persistToDisk: false,
      ));
      await writer.start(
        tempDirPath: tempDir.path,
        fileName: 'interceptly_mem_only.tmp',
      );

      final nextEntry = writer.results.first;
      writer.send(_capture('mem-1', body: _bytes(1000, 42)));
      final entry = await nextEntry.timeout(const Duration(seconds: 5));

      expect(entry.bodyLocation, equals(BodyLocation.memory));
      expect(entry.fileOffset, isNull);
      expect(entry.fileLength, isNull);
      expect(entry.inlineResponseBody, isNotNull);
      expect(entry.inlineResponseBody!.length, equals(1000));

      await writer.dispose();
    });
  });
}

