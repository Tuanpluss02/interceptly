import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/engine/body_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('body_store_test_');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('BodyStore core lifecycle', () {
    test('initForWrite, append, and readBytes roundtrip', () async {
      final store = BodyStore();
      addTearDown(store.dispose);

      await store.initForWrite(tempDir.path, fileName: 'session.tmp');
      expect(store.isWritable, isTrue);
      expect(store.currentOffset, equals(0));
      expect(store.rotationCount, equals(0));

      final bytes1 = Uint8List.fromList([10, 20, 30, 40]);
      final (offset1, len1) = await store.append(bytes1);
      expect(offset1, equals(0));
      expect(len1, equals(4));
      expect(store.currentOffset, equals(4));

      final bytes2 = Uint8List.fromList([50, 60]);
      final (offset2, len2) = await store.append(bytes2);
      expect(offset2, equals(4));
      expect(len2, equals(2));
      expect(store.currentOffset, equals(6));

      final filePath = '${tempDir.path}/session.tmp';
      final read1 = await BodyStore.readBytes(filePath, offset1, len1);
      expect(read1, equals(bytes1));

      final read2 = await BodyStore.readBytes(filePath, offset2, len2);
      expect(read2, equals(bytes2));
    });

    test('rotates automatically when exceeding maxFileBytes', () async {
      var rotated = 0;
      final store = BodyStore(
        maxFileBytes: 10,
        onRotate: (r) => rotated = r,
      );
      addTearDown(store.dispose);

      await store.initForWrite(tempDir.path, fileName: 'rot.tmp');
      await store.append(Uint8List.fromList([1, 2, 3, 4, 5, 6]));
      expect(store.rotationCount, equals(0));
      expect(rotated, equals(0));

      // Next append of 5 bytes exceeds 10 bytes -> triggers rotation
      final (offset, len) =
          await store.append(Uint8List.fromList([7, 8, 9, 10, 11]));
      expect(offset, equals(0));
      expect(len, equals(5));
      expect(store.rotationCount, equals(1));
      expect(rotated, equals(1));
      expect(store.currentOffset, equals(5));
    });
  });

  group('BodyStore resetFile recovery & degradation', () {
    test(
        'successful resetFile recreates file, resets offset, and advances rotation',
        () async {
      var rotationNotified = 0;
      final store = BodyStore(
        onRotate: (r) => rotationNotified = r,
      );
      addTearDown(store.dispose);

      await store.initForWrite(tempDir.path, fileName: 'original.tmp');
      await store.append(Uint8List.fromList([1, 2, 3]));
      expect(store.currentOffset, equals(3));
      expect(store.rotationCount, equals(0));

      final ok = await store.resetFile(tempDir.path, fileName: 'reset.tmp');
      expect(ok, isTrue);
      expect(store.isWritable, isTrue);
      expect(store.currentOffset, equals(0));
      expect(store.rotationCount, equals(1));
      expect(rotationNotified, equals(1));

      final (offset, len) = await store.append(Uint8List.fromList([99]));
      expect(offset, equals(0));
      expect(len, equals(1));
      expect(store.currentOffset, equals(1));
    });

    test(
        'non-destructive reset failure restores old file handle and allows subsequent append',
        () async {
      final store = BodyStore();
      addTearDown(store.dispose);

      await store.initForWrite(tempDir.path, fileName: 'intact.tmp');
      await store.append(Uint8List.fromList([1, 2, 3]));
      expect(store.currentOffset, equals(3));
      expect(store.rotationCount, equals(0));

      // Create a file blocking directory creation to force reset failure on a different path
      final blockerFile = File('${tempDir.path}/blocker_file');
      await blockerFile.writeAsString('I am a file, not a directory');

      final ok = await store.resetFile(blockerFile.path, fileName: 'fail.tmp');
      expect(ok, isFalse);
      // Rollback verified: old handle restored, old offset preserved, not rotated
      expect(store.isWritable, isTrue);
      expect(store.currentOffset, equals(3));
      expect(store.rotationCount, equals(0));

      // Appending still works cleanly without TypeError or null check crash
      final (offset, len) = await store.append(Uint8List.fromList([4, 5]));
      expect(offset, equals(3));
      expect(len, equals(2));
      expect(store.currentOffset, equals(5));

      final readAll =
          await BodyStore.readBytes('${tempDir.path}/intact.tmp', 0, 5);
      expect(readAll, equals(Uint8List.fromList([1, 2, 3, 4, 5])));
    });

    test(
        'destructive same-path reset failure advances rotation and truthfully degrades',
        () async {
      var rotationNotified = 0;
      final store = BodyStore(
        onRotate: (r) => rotationNotified = r,
      );
      addTearDown(store.dispose);

      final readOnlySubdir = Directory('${tempDir.path}/ro_dir');
      await readOnlySubdir.create();

      await store.initForWrite(readOnlySubdir.path, fileName: 'same_path.tmp');
      await store.append(Uint8List.fromList([1, 2, 3]));
      expect(store.currentOffset, equals(3));

      // Delete the file and lock the directory so recreation fails
      await Process.run('chmod', ['555', readOnlySubdir.path]);

      try {
        final ok = await store.resetFile(readOnlySubdir.path,
            fileName: 'same_path.tmp');
        expect(ok, isFalse);
        // Destructive failure: rotation advanced, store degraded
        expect(store.isWritable, isFalse);
        expect(store.currentOffset, equals(0));
        expect(store.rotationCount, equals(1));
        expect(rotationNotified, equals(1));

        // Subsequent append throws FileSystemException instead of crashing with TypeError
        expect(
          () => store.append(Uint8List.fromList([4])),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        await Process.run('chmod', ['777', readOnlySubdir.path]);
      }
    });
  });
}
