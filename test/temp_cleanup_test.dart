import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/session/body_store.dart';
import 'package:interceptly/src/session/inspector_session.dart';

/// Specification implementation of orphan purge contract used for verification.
Future<int> _purgeOrphanedTempFiles(
  String dirPath, {
  String? currentFileName,
}) async {
  var purgedCount = 0;
  final dir = Directory(dirPath);
  if (!await dir.exists()) return 0;

  final entities = await dir.list().toList();
  for (final entity in entities) {
    if (entity is File) {
      final name = entity.uri.pathSegments.last;
      if (name.startsWith('interceptly_') &&
          name.endsWith('.tmp') &&
          name != currentFileName) {
        try {
          await entity.delete();
          purgedCount++;
        } catch (_) {}
      }
    }
  }
  return purgedCount;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('temp_cleanup_test_');
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Temp File Management: BodyStore Lifecycle', () {
    test('initForWrite creates file and dispose removes it', () async {
      final store = BodyStore();
      const fileName = 'interceptly_active_test.tmp';
      await store.initForWrite(tempDir.path, fileName: fileName);

      final sessionFile = File('${tempDir.path}/$fileName');
      expect(await sessionFile.exists(), isTrue);

      final (offset, length) = await store.append(Uint8List.fromList([1, 2, 3, 4]));
      expect(offset, equals(0));
      expect(length, equals(4));

      await store.dispose();
      expect(await sessionFile.exists(), isFalse);
    });

    test('resetFile clears old data and re-initializes handle', () async {
      final store = BodyStore();
      const fileName = 'interceptly_reset_test.tmp';
      await store.initForWrite(tempDir.path, fileName: fileName);

      final sessionFile = File('${tempDir.path}/$fileName');
      await store.append(Uint8List.fromList([10, 20, 30]));
      expect(await sessionFile.length(), equals(3));

      await store.resetFile(tempDir.path, fileName: fileName);
      expect(await sessionFile.length(), equals(0));

      final (offset, length) = await store.append(Uint8List.fromList([99]));
      expect(offset, equals(0));
      expect(length, equals(1));
      expect(await sessionFile.length(), equals(1));

      await store.dispose();
    });

    test('Multiple concurrent stores manage independent files', () async {
      final store1 = BodyStore();
      final store2 = BodyStore();

      await store1.initForWrite(tempDir.path, fileName: 'interceptly_store_1.tmp');
      await store2.initForWrite(tempDir.path, fileName: 'interceptly_store_2.tmp');

      final file1 = File('${tempDir.path}/interceptly_store_1.tmp');
      final file2 = File('${tempDir.path}/interceptly_store_2.tmp');

      expect(await file1.exists(), isTrue);
      expect(await file2.exists(), isTrue);

      await store1.dispose();
      expect(await file1.exists(), isFalse);
      expect(await file2.exists(), isTrue);

      await store2.dispose();
      expect(await file2.exists(), isFalse);
    });
  });

  group('Temp File Management: Orphan Purge Algorithm Contract (F13)', () {
    test('Purges orphan session files while preserving active session file', () async {
      final orphan1 = File('${tempDir.path}/interceptly_old_session_1.tmp');
      final orphan2 = File('${tempDir.path}/interceptly_old_session_2.tmp');
      final active = File('${tempDir.path}/interceptly_active_session.tmp');

      await orphan1.writeAsString('orphan data 1');
      await orphan2.writeAsString('orphan data 2');
      await active.writeAsString('active session data');

      final purged = await _purgeOrphanedTempFiles(
        tempDir.path,
        currentFileName: 'interceptly_active_session.tmp',
      );

      expect(purged, equals(2));
      expect(await orphan1.exists(), isFalse);
      expect(await orphan2.exists(), isFalse);
      expect(await active.exists(), isTrue);
    });

    test('Strictly preserves non-interceptly files and subdirectories', () async {
      final nonTmp = File('${tempDir.path}/interceptly_data.json');
      final otherFile = File('${tempDir.path}/user_document.pdf');
      final dbFile = File('${tempDir.path}/sqlite_cache.db');
      final orphan = File('${tempDir.path}/interceptly_crash_session.tmp');
      final subDir = Directory('${tempDir.path}/interceptly_cache_dir');

      await nonTmp.writeAsString('{"key": "value"}');
      await otherFile.writeAsString('pdf content');
      await dbFile.writeAsString('binary db');
      await orphan.writeAsString('corrupted');
      await subDir.create();

      final purged = await _purgeOrphanedTempFiles(tempDir.path);

      expect(purged, equals(1));
      expect(await orphan.exists(), isFalse);
      expect(await nonTmp.exists(), isTrue);
      expect(await otherFile.exists(), isTrue);
      expect(await dbFile.exists(), isTrue);
      expect(await subDir.exists(), isTrue);
    });

    test('Gracefully handles empty or missing directory', () async {
      final emptyDir = await tempDir.createTemp('empty_');
      final purgedEmpty = await _purgeOrphanedTempFiles(emptyDir.path);
      expect(purgedEmpty, equals(0));

      final missingPath = '${tempDir.path}/non_existent_folder';
      final purgedMissing = await _purgeOrphanedTempFiles(missingPath);
      expect(purgedMissing, equals(0));
    });
  });

  group('Temp File Management: InspectorSession Lifecycle & Cleanup', () {
    test('BodyStore.purgeOrphanedTempFiles purges orphaned files and ignores active file', () async {
      final orphan = File('${tempDir.path}/interceptly_crashed_1.tmp');
      final active = File('${tempDir.path}/interceptly_active_2.tmp');
      await orphan.writeAsString('crashed');
      await active.writeAsString('active');

      final count = await BodyStore.purgeOrphanedTempFiles(
        tempDir.path,
        currentFileName: 'interceptly_active_2.tmp',
      );

      expect(count, equals(1));
      expect(await orphan.exists(), isFalse);
      expect(await active.exists(), isTrue);
    });

    test('BodyStore.openReadHandle and readWithHandle read slice correctly', () async {
      final store = BodyStore();
      const fileName = 'interceptly_handle_test.tmp';
      await store.initForWrite(tempDir.path, fileName: fileName);
      final filePath = '${tempDir.path}/$fileName';

      await store.append(Uint8List.fromList([10, 20, 30, 40, 50]));

      final raf = await BodyStore.openReadHandle(filePath);
      try {
        final bytes = await BodyStore.readWithHandle(raf, 1, 3);
        expect(bytes, equals(Uint8List.fromList([20, 30, 40])));
      } finally {
        await raf.close();
      }

      await store.dispose();
    });

    test('InspectorSession cleans up session file on dispose()', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (call.method == 'getTemporaryDirectory') return tempDir.path;
          return null;
        },
      );

      final session = InspectorSession();
      await session.initialize();

      final files = tempDir.listSync().whereType<File>().toList();
      final hasSessionFile = files.any(
        (f) => f.uri.pathSegments.last.startsWith('interceptly_') &&
            f.uri.pathSegments.last.endsWith('.tmp'),
      );
      expect(hasSessionFile, isTrue);

      await session.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final remaining = tempDir.listSync().whereType<File>().toList();
      final sessionStillExists = remaining.any(
        (f) => f.uri.pathSegments.last.startsWith('interceptly_') &&
            f.uri.pathSegments.last.endsWith('.tmp'),
      );
      expect(sessionStillExists, isFalse);
    });

    test('InspectorSession.initialize() automatically purges prior orphan session files', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (call.method == 'getTemporaryDirectory') return tempDir.path;
          return null;
        },
      );

      final orphan1 = File('${tempDir.path}/interceptly_prior_crash_1.tmp');
      final orphan2 = File('${tempDir.path}/interceptly_prior_crash_2.tmp');
      final regularFile = File('${tempDir.path}/regular_file.txt');
      await orphan1.writeAsString('prior crash 1');
      await orphan2.writeAsString('prior crash 2');
      await regularFile.writeAsString('keep me');

      final session = InspectorSession();
      await session.initialize();

      expect(await orphan1.exists(), isFalse);
      expect(await orphan2.exists(), isFalse);
      expect(await regularFile.exists(), isTrue);

      await session.dispose();
    });
  });
}
