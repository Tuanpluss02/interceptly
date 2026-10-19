// ignore_for_file: invalid_use_of_internal_member
@Tags(['stress'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/body_store.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/engine/master_search_controller.dart';

Uint8List _createPackedBody({
  String? requestBody,
  String? responseBody,
  bool truncated = false,
}) {
  final reqBytes =
      requestBody != null ? Uint8List.fromList(utf8.encode(requestBody)) : null;
  final resBytes = responseBody != null
      ? Uint8List.fromList(utf8.encode(responseBody))
      : null;

  final total = 4 + (reqBytes?.length ?? 0) + 4 + (resBytes?.length ?? 0) + 1;
  final out = Uint8List(total);
  final data = ByteData.sublistView(out);
  var offset = 0;

  if (reqBytes == null) {
    data.setUint32(offset, 0xFFFFFFFF, Endian.big);
    offset += 4;
  } else {
    data.setUint32(offset, reqBytes.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + reqBytes.length, reqBytes);
    offset += reqBytes.length;
  }

  if (resBytes == null) {
    data.setUint32(offset, 0xFFFFFFFF, Endian.big);
    offset += 4;
  } else {
    data.setUint32(offset, resBytes.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + resBytes.length, resBytes);
    offset += resBytes.length;
  }

  out[offset] = truncated ? 1 : 0;
  return out;
}

IndexEntry _buildTestEntry({
  required String id,
  String method = 'GET',
  String url = 'https://api.example.com/items',
  int statusCode = 200,
  int durationMs = 25,
  int requestSizeBytes = 128,
  int responseSizeBytes = 256,
  bool hasError = false,
  BodyTruncation responseTruncation = const BodyTruncation.complete(0),
  Map<String, String> requestHeaders = const {},
  Map<String, String> responseHeaders = const {},
  String? requestContentType = 'application/json',
  String? responseContentType = 'application/json',
  String? errorMessage,
  BodyLocation bodyLocation = BodyLocation.memory,
  Uint8List? inlineRequestBody,
  Uint8List? inlineResponseBody,
  int? fileOffset,
  int? fileLength,
}) {
  return IndexEntry(
    id: id,
    method: method,
    url: url,
    statusCode: statusCode,
    durationMs: durationMs,
    requestSizeBytes: requestSizeBytes,
    responseSizeBytes: responseSizeBytes,
    timestamp: DateTime(2026, 3, 15, 10, 0, 0),
    hasError: hasError,
    requestTruncation: const BodyTruncation.complete(0),
    responseTruncation: responseTruncation,
    requestHeaders: requestHeaders,
    responseHeaders: responseHeaders,
    requestContentType: requestContentType,
    responseContentType: responseContentType,
    errorMessage: errorMessage,
    bodyLocation: bodyLocation,
    inlineRequestBody: inlineRequestBody,
    inlineResponseBody: inlineResponseBody,
    fileOffset: fileOffset,
    fileLength: fileLength,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('challenger_m3_2_');
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Challenge Area 1: Lifecycle Temp Cleanup & Boundary Stress', () {
    test(
        'purges 150+ simulated orphan files while strictly preserving active file',
        () async {
      const orphanCount = 150;
      final orphanFiles = <File>[];
      for (var i = 0; i < orphanCount; i++) {
        final f = File('${tempDir.path}/interceptly_orphan_$i.tmp');
        await f.writeAsString('orphan_payload_$i');
        orphanFiles.add(f);
      }

      final activeFile = File('${tempDir.path}/interceptly_active_current.tmp');
      await activeFile.writeAsString('active_session_payload');

      final purged = await BodyStore.purgeOrphanedTempFiles(
        tempDir.path,
        currentFileName: 'interceptly_active_current.tmp',
      );

      expect(purged, equals(orphanCount));
      for (final f in orphanFiles) {
        expect(await f.exists(), isFalse);
      }
      expect(await activeFile.exists(), isTrue);
      expect(await activeFile.readAsString(), equals('active_session_payload'));
    });

    test(
        'preserves active file when currentFileName is passed as full absolute path',
        () async {
      final orphan = File('${tempDir.path}/interceptly_old_1.tmp');
      await orphan.writeAsString('orphan');
      final active = File('${tempDir.path}/interceptly_my_session.tmp');
      await active.writeAsString('keep_me');

      final purged = await BodyStore.purgeOrphanedTempFiles(
        tempDir.path,
        currentFileName: active.path,
      );

      expect(purged, equals(1));
      expect(await orphan.exists(), isFalse);
      expect(await active.exists(), isTrue);
    });

    test(
        'strictly preserves non-interceptly files, atypical extensions, and subdirectories',
        () async {
      final filesToKeep = [
        File('${tempDir.path}/interceptly_notes.txt'),
        File('${tempDir.path}/interceptly_config.json'),
        File('${tempDir.path}/user_data.tmp'),
        File('${tempDir.path}/other_interceptly_file.tmp.bak'),
        File('${tempDir.path}/interceptly_without_extension'),
        File('${tempDir.path}/system.tmp'),
      ];

      for (final f in filesToKeep) {
        await f.writeAsString('preserve content');
      }

      final subdirsToKeep = [
        Directory('${tempDir.path}/interceptly_subfolder.tmp'),
        Directory('${tempDir.path}/interceptly_cache'),
        Directory('${tempDir.path}/nested_dir'),
      ];

      for (final d in subdirsToKeep) {
        await d.create();
        await File('${d.path}/nested.tmp').writeAsString('nested data');
      }

      final orphan1 = File('${tempDir.path}/interceptly_crash_99.tmp');
      final orphan2 = File('${tempDir.path}/interceptly_crash_100.tmp');
      await orphan1.writeAsString('orphan1');
      await orphan2.writeAsString('orphan2');

      final purged = await BodyStore.purgeOrphanedTempFiles(tempDir.path);

      expect(purged, equals(2));
      expect(await orphan1.exists(), isFalse);
      expect(await orphan2.exists(), isFalse);

      for (final f in filesToKeep) {
        expect(await f.exists(), isTrue);
      }
      for (final d in subdirsToKeep) {
        expect(await d.exists(), isTrue);
        expect(await File('${d.path}/nested.tmp').exists(), isTrue);
      }
    });

    test('handles empty directory and nonexistent directory gracefully',
        () async {
      final emptySubdir = await tempDir.createTemp('empty_test_');
      final purgedEmpty =
          await BodyStore.purgeOrphanedTempFiles(emptySubdir.path);
      expect(purgedEmpty, equals(0));

      final nonExistentPath = '${tempDir.path}/missing_folder_12345';
      final purgedMissing =
          await BodyStore.purgeOrphanedTempFiles(nonExistentPath);
      expect(purgedMissing, equals(0));
    });

    test('recovers gracefully when a file delete throws FileSystemException',
        () async {
      final orphan1 = File('${tempDir.path}/interceptly_normal_1.tmp');
      await orphan1.writeAsString('normal');

      final lockedDir = Directory('${tempDir.path}/interceptly_locked.tmp');
      await lockedDir.create();

      final orphan2 = File('${tempDir.path}/interceptly_normal_2.tmp');
      await orphan2.writeAsString('normal2');

      final purged = await BodyStore.purgeOrphanedTempFiles(tempDir.path);
      expect(purged, equals(2));
      expect(await orphan1.exists(), isFalse);
      expect(await orphan2.exists(), isFalse);
      expect(await lockedDir.exists(), isTrue);
    });
  });

  group('Challenge Area 2: InspectorSession Auto-Purge Lifecycle', () {
    test(
        'InspectorSession initialization detects and purges prior orphans while preserving its active file',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (call.method == 'getTemporaryDirectory') return tempDir.path;
          return null;
        },
      );

      final priorOrphan1 =
          File('${tempDir.path}/interceptly_old_session_1.tmp');
      final priorOrphan2 =
          File('${tempDir.path}/interceptly_old_session_2.tmp');
      final regularFile = File('${tempDir.path}/app_cache.db');
      final subFolder = Directory('${tempDir.path}/session_logs');

      await priorOrphan1.writeAsString('crashed session 1');
      await priorOrphan1
          .setLastModified(DateTime.now().subtract(const Duration(hours: 25)));
      await priorOrphan2.writeAsString('crashed session 2');
      await priorOrphan2
          .setLastModified(DateTime.now().subtract(const Duration(hours: 25)));
      await regularFile.writeAsString('cache database');
      await subFolder.create();

      final session = InterceptlyEngine();
      await session.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await priorOrphan1.exists(), isFalse);
      expect(await priorOrphan2.exists(), isFalse);
      expect(await regularFile.exists(), isTrue);
      expect(await subFolder.exists(), isTrue);

      final activeFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.uri.pathSegments.last.startsWith('interceptly_') &&
              f.uri.pathSegments.last.endsWith('.tmp'))
          .toList();
      expect(activeFiles.length, inInclusiveRange(1, 2));
      final activeFile =
          activeFiles.firstWhere((f) => f.path.contains('_session.tmp'));

      session.record(RawCapture(
        id: 'req_1',
        method: 'POST',
        url: 'https://api.example.com/login',
        statusCode: 200,
        durationMs: 50,
        timestamp: DateTime.now(),
        requestHeaders: const {},
        responseHeaders: const {'content-type': 'application/json'},
        responseContentType: 'application/json',
        responseBodyBytes: RawCapture.wrapBytes(
          Uint8List.fromList(utf8.encode('{"token": "xyz123"}')),
        ),
      ));

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await activeFile.exists(), isTrue);

      await session.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      for (final f in activeFiles) {
        expect(await f.exists(), isFalse);
      }
    });

    test('Consecutive simulated crash session cleaned up by next session',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (call.method == 'getTemporaryDirectory') return tempDir.path;
          return null;
        },
      );

      final crashedSessionFile =
          File('${tempDir.path}/interceptly_crash_session.tmp');
      await crashedSessionFile.writeAsString('unclosed session from crash');
      await crashedSessionFile
          .setLastModified(DateTime.now().subtract(const Duration(hours: 25)));

      final newSession = InterceptlyEngine();
      await newSession.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await crashedSessionFile.exists(), isFalse);

      final files = tempDir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.uri.pathSegments.last.startsWith('interceptly_') &&
              f.uri.pathSegments.last.endsWith('.tmp'))
          .toList();
      expect(files.length, inInclusiveRange(1, 2));

      await newSession.dispose();
    });
  });

  group(
      'Challenge Area 3: MasterSearchController Boundary Cases & Concurrency Stress',
      () {
    late MasterSearchController controller;
    late BodyStore store;
    late String backingFilePath;

    setUp(() async {
      controller = MasterSearchController();
      store = BodyStore();
      await store.initForWrite(tempDir.path, fileName: 'search_backing.tmp');
      backingFilePath = '${tempDir.path}/search_backing.tmp';
    });

    tearDown(() async {
      controller.dispose();
      await store.dispose();
    });

    test(
        '0 file entries: skips Phase 3 safely when all entries are memory-backed or list is empty',
        () async {
      await controller.start(
        query: 'search_term',
        allEntries: [],
        filePath: backingFilePath,
      );
      expect(controller.results, isNotNull);
      expect(controller.results, isEmpty);
      expect(controller.isScanningFiles, isFalse);

      final memEntry = _buildTestEntry(
        id: 'mem_1',
        url: 'https://api.example.com/test',
        bodyLocation: BodyLocation.memory,
      );
      await controller.start(
        query: 'test',
        allEntries: [memEntry],
        filePath: backingFilePath,
      );
      expect(controller.results!.length, equals(1));
      expect(controller.isScanningFiles, isFalse);
    });

    test('skips entries with missing fileOffset or fileLength without errors',
        () async {
      final entryNullOffset = _buildTestEntry(
        id: 'null_offset',
        bodyLocation: BodyLocation.file,
        fileOffset: null,
        fileLength: 50,
      );
      final entryNullLength = _buildTestEntry(
        id: 'null_length',
        bodyLocation: BodyLocation.file,
        fileOffset: 0,
        fileLength: null,
      );

      await controller.start(
        query: 'search_term',
        allEntries: [entryNullOffset, entryNullLength],
        filePath: backingFilePath,
      );

      expect(controller.results, isNotNull);
      expect(controller.results, isEmpty);
      expect(controller.isScanningFiles, isFalse);
    });

    test(
        'corrupt file offsets (beyond EOF, negative, zero length) handled gracefully without crash',
        () async {
      final packed = _createPackedBody(
        requestBody: '{"valid": "data"}',
        responseBody: '{"status": "ok"}',
      );
      await store.append(packed);

      final outOfBoundsEntry = _buildTestEntry(
        id: 'oob',
        bodyLocation: BodyLocation.file,
        fileOffset: 999999,
        fileLength: 1000,
      );
      final zeroLengthEntry = _buildTestEntry(
        id: 'zero_len',
        bodyLocation: BodyLocation.file,
        fileOffset: 0,
        fileLength: 0,
      );

      await controller.start(
        query: 'test_query',
        allEntries: [outOfBoundsEntry, zeroLengthEntry],
        filePath: backingFilePath,
      );

      expect(controller.results, isNotNull);
      expect(controller.results, isEmpty);
      expect(controller.isScanningFiles, isFalse);
    });

    test('corrupt or garbage file bytes decoded safely without exception',
        () async {
      final corruptRaf =
          await File(backingFilePath).open(mode: FileMode.writeOnlyAppend);
      await corruptRaf
          .writeFrom(Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]));
      await corruptRaf.close();

      final corruptEntry = _buildTestEntry(
        id: 'corrupt',
        bodyLocation: BodyLocation.file,
        fileOffset: 0,
        fileLength: 6,
      );

      await controller.start(
        query: 'payload',
        allEntries: [corruptEntry],
        filePath: backingFilePath,
      );

      expect(controller.results, isNotNull);
      expect(controller.results, isEmpty);
      expect(controller.isScanningFiles, isFalse);
    });

    test('missing backing file handled gracefully without unhandled exception',
        () async {
      final entry = _buildTestEntry(
        id: 'missing_backing',
        bodyLocation: BodyLocation.file,
        fileOffset: 0,
        fileLength: 50,
      );

      await controller.start(
        query: 'missing_file_query',
        allEntries: [entry],
        filePath: '${tempDir.path}/does_not_exist_99.tmp',
      );

      expect(controller.results, isNotNull);
      expect(controller.results, isEmpty);
      expect(controller.isScanningFiles, isFalse);
    });

    test('empty and whitespace-only queries trigger cancel immediately',
        () async {
      final entry = _buildTestEntry(id: 'entry_1', url: 'https://example.com');

      for (final emptyQuery in ['', '   ', '\t\n  \r']) {
        await controller.start(
          query: emptyQuery,
          allEntries: [entry],
          filePath: backingFilePath,
        );

        expect(controller.isActive, isFalse);
        expect(controller.query, isNull);
        expect(controller.results, isNull);
      }
    });

    test(
        'search reset during active scan cancels in-flight operation without race exception',
        () async {
      final entries = <IndexEntry>[];
      for (var i = 0; i < 300; i++) {
        final packed = _createPackedBody(
          requestBody: '{"seq": $i, "code": "batch_$i"}',
          responseBody: '{"ack": true}',
        );
        final (offset, length) = await store.append(packed);
        entries.add(
          _buildTestEntry(
            id: 'e_$i',
            url: 'https://api.example.com/record/$i',
            bodyLocation: BodyLocation.file,
            fileOffset: offset,
            fileLength: length,
          ),
        );
      }

      final searchFuture = controller.start(
        query: 'batch_',
        allEntries: entries,
        filePath: backingFilePath,
      );

      await Future<void>.delayed(const Duration(milliseconds: 5));
      controller.reset();

      await searchFuture;

      expect(controller.query, isNull);
      expect(controller.results, isNull);
      expect(controller.isActive, isFalse);
    });

    test('search cancel during active scan clears state and notifies listeners',
        () async {
      final entries = <IndexEntry>[];
      for (var i = 0; i < 300; i++) {
        final bodyBytes =
            Uint8List.fromList(utf8.encode('{"item": $i, "tag": "bulk_$i"}'));
        entries.add(
          _buildTestEntry(
            id: 'mem_$i',
            url: 'https://api.example.com/item/$i',
            bodyLocation: BodyLocation.memory,
            inlineResponseBody: bodyBytes,
          ),
        );
      }

      var notifiedAfterCancel = false;
      final searchFuture = controller.start(
        query: 'bulk_',
        allEntries: entries,
        filePath: null,
      );

      await Future<void>.delayed(const Duration(milliseconds: 5));
      controller.addListener(() {
        if (!controller.isActive) {
          notifiedAfterCancel = true;
        }
      });
      controller.cancel();

      await searchFuture;

      expect(controller.isActive, isFalse);
      expect(controller.query, isNull);
      expect(controller.results, isNull);
      expect(notifiedAfterCancel, isTrue);
    });

    test('search reset during Phase 1 when matching entry follows yield',
        () async {
      final e1 =
          _buildTestEntry(id: 'e1', url: 'https://api.example.com/other');
      final e2 =
          _buildTestEntry(id: 'e2', url: 'https://api.example.com/target');

      final searchFuture = controller.start(
        query: 'target',
        allEntries: [e1, e2],
        filePath: null,
      );
      controller.reset();
      await searchFuture;

      expect(controller.query, isNull);
      expect(controller.results, isNull);
    });

    test(
        'rapid alternating start, reset, and start operations resolve to final query',
        () async {
      final e1 =
          _buildTestEntry(id: 'e1', url: 'https://api.example.com/alpha');
      final e2 = _buildTestEntry(id: 'e2', url: 'https://api.example.com/beta');
      final e3 =
          _buildTestEntry(id: 'e3', url: 'https://api.example.com/gamma');

      controller.start(
          query: 'alpha', allEntries: [e1, e2, e3], filePath: null);
      controller.reset();
      controller.start(query: 'beta', allEntries: [e1, e2, e3], filePath: null);
      controller.reset();
      await controller.start(
          query: 'gamma', allEntries: [e1, e2, e3], filePath: null);

      expect(controller.query, equals('gamma'));
      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('e3'));
    });

    test(
        'new search started during Phase 3 does not get polluted by prior file scan matches',
        () async {
      final packed1 = _createPackedBody(
        requestBody: '{"payload": "first_query_match"}',
        responseBody: '{"ok": true}',
      );
      final (offset1, length1) = await store.append(packed1);

      final packed2 = _createPackedBody(
        requestBody: '{"payload": "second_query_match"}',
        responseBody: '{"ok": true}',
      );
      final (offset2, length2) = await store.append(packed2);

      final e1 = _buildTestEntry(
        id: 'file_1',
        url: 'https://api.example.com/file1',
        bodyLocation: BodyLocation.file,
        fileOffset: offset1,
        fileLength: length1,
      );
      final e2 = _buildTestEntry(
        id: 'file_2',
        url: 'https://api.example.com/file2',
        bodyLocation: BodyLocation.file,
        fileOffset: offset2,
        fileLength: length2,
      );

      final future1 = controller.start(
        query: 'first_query_match',
        allEntries: [e1, e2],
        filePath: backingFilePath,
      );
      final future2 = controller.start(
        query: 'second_query_match',
        allEntries: [e1, e2],
        filePath: backingFilePath,
      );

      await Future.wait([future1, future2]);

      expect(controller.query, equals('second_query_match'));
      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('file_2'));
    });
  });
}
