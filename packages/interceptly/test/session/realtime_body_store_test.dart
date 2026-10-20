// ignore_for_file: invalid_use_of_internal_member

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/engine/realtime_body_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('realtime_body_store_test_');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('RealtimeBodyStore', () {
    test('initializes and reports state correctly', () async {
      final store = RealtimeBodyStore();
      addTearDown(store.dispose);

      expect(store.isInitialized, isFalse);
      expect(store.currentOffset, equals(0));
      expect(store.rotationCount, equals(0));

      await store.initForWrite(tempDir.path);

      expect(store.isInitialized, isTrue);
      expect(store.currentOffset, equals(0));
      expect(store.rotationCount, equals(0));
    });

    test('sequential raw binary append and exact read-back', () async {
      final store = RealtimeBodyStore();
      addTearDown(store.dispose);
      await store.initForWrite(tempDir.path);

      final payload1 = Uint8List.fromList([1, 2, 3, 4, 5]);
      final payload2 = Uint8List.fromList([10, 20, 30, 40]);

      final res1 = await store.append(payload1);
      expect(res1.$1, equals(0)); // offset
      expect(res1.$2, equals(5)); // length
      expect(res1.$3, equals(0)); // rotationCount

      final res2 = await store.append(payload2);
      expect(res2.$1, equals(5));
      expect(res2.$2, equals(4));
      expect(res2.$3, equals(0));

      expect(store.currentOffset, equals(9));

      final read1 = await store.readBytes(res1.$1, res1.$2);
      expect(read1, equals(payload1));

      final read2 = await store.readBytes(res2.$1, res2.$2);
      expect(read2, equals(payload2));
    });

    test(
        'serializes concurrent appends without race conditions or offset corruption',
        () async {
      final store = RealtimeBodyStore();
      addTearDown(store.dispose);
      await store.initForWrite(tempDir.path);

      const count = 20;
      final payloads =
          List.generate(count, (i) => Uint8List.fromList(List.filled(100, i)));

      // Dispatch 20 simultaneous append calls concurrently
      final futures = payloads.map((p) => store.append(p));
      final results = await Future.wait(futures);

      expect(results.length, equals(count));
      expect(store.currentOffset, equals(count * 100));

      // Verify that every single offset is unique, strictly monotonic (increasing by 100), and non-overlapping
      final offsets = results.map((r) => r.$1).toList();
      final sortedOffsets = List<int>.from(offsets)..sort();
      expect(offsets, equals(sortedOffsets),
          reason: 'Offsets must preserve submission order');

      for (var i = 0; i < count; i++) {
        expect(results[i].$1, equals(i * 100));
        expect(results[i].$2, equals(100));
        expect(results[i].$3, equals(0));

        final readBack = await store.readBytes(results[i].$1, results[i].$2);
        expect(readBack, equals(payloads[i]));
      }
    });

    test(
        'rotates file when capacity is exceeded, resetting offset and bumping rotationCount',
        () async {
      // 100 bytes max capacity
      final store = RealtimeBodyStore(maxFileBytes: 100);
      addTearDown(store.dispose);
      await store.initForWrite(tempDir.path);

      final payload = Uint8List.fromList(List.filled(60, 42));

      final res1 = await store.append(payload);
      expect(res1.$1, equals(0));
      expect(res1.$2, equals(60));
      expect(res1.$3, equals(0));
      expect(store.rotationCount, equals(0));

      // Appending another 60 bytes exceeds 100 bytes maxFileBytes -> triggers automatic rotation
      final payload2 = Uint8List.fromList(List.filled(60, 99));
      final res2 = await store.append(payload2);

      expect(res2.$1, equals(0), reason: 'Offset resets to 0 upon rotation');
      expect(res2.$2, equals(60));
      expect(res2.$3, equals(1), reason: 'Rotation count increments');
      expect(store.rotationCount, equals(1));
      expect(store.currentOffset, equals(60));

      final read2 = await store.readBytes(res2.$1, res2.$2);
      expect(read2, equals(payload2));
    });

    test('dispose closes handle and deletes file cleanly', () async {
      final store = RealtimeBodyStore();
      await store.initForWrite(tempDir.path, fileName: 'test_dispose.tmp');
      final file = File('${tempDir.path}/test_dispose.tmp');
      expect(await file.exists(), isTrue);

      await store.dispose();
      expect(await file.exists(), isFalse);
      expect(store.isInitialized, isFalse);
    });

    test(
        'dispose during initForWrite cleans up handle and remains uninitialized',
        () async {
      final store = RealtimeBodyStore();
      final initFuture = store.initForWrite(tempDir.path,
          fileName: 'test_mid_init_dispose.tmp');
      final disposeFuture = store.dispose();
      await Future.wait([initFuture, disposeFuture]);

      expect(store.isInitialized, isFalse);
    });

    test('enforces backpressure guard when pending writes exceed limit',
        () async {
      final store = RealtimeBodyStore(maxPendingWrites: 20);
      addTearDown(store.dispose);
      await store.initForWrite(tempDir.path);

      final futures = <Future<dynamic>>[];
      for (var i = 0; i < 20; i++) {
        futures.add(store.append(Uint8List.fromList([i])));
      }

      expect(
        () => store.append(Uint8List.fromList([21])),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('saturated (backpressure limit 20 exceeded)'),
        )),
      );

      await Future.wait(futures);
      expect(store.pendingWrites, equals(0));
    });
  });
}
