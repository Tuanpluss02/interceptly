import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';
import 'package:interceptly/src/session/body_decode_service.dart';
import 'package:interceptly/src/session/detail_loader.dart';
import 'package:interceptly/src/session/inspector_session.dart';
import 'package:interceptly/src/session/memory_index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('body_store_eof_test_');
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

  IndexEntry createFileEntry({
    required String id,
    required int fileOffset,
    required int fileLength,
  }) {
    return IndexEntry(
      id: id,
      method: 'POST',
      url: 'https://api.example.com/data',
      statusCode: 200,
      durationMs: 30,
      requestSizeBytes: 200,
      responseSizeBytes: 200,
      timestamp: DateTime.now(),
      hasError: false,
      bodyLocation: BodyLocation.file,
      inlineRequestBody: null,
      inlineResponseBody: null,
      requestHeaders: const {},
      responseHeaders: const {},
      requestContentType: 'application/json',
      responseContentType: 'application/json',
      errorType: null,
      errorMessage: null,
      requestTruncation: const BodyTruncation.complete(200),
      responseTruncation: const BodyTruncation.complete(200),
      fileOffset: fileOffset,
      fileLength: fileLength,
    );
  }

  group('BodyStore EOF and Truncated Read Resilience in DetailLoader', () {
    test('reading past file offset returns unavailable placeholder', () async {
      final dummyFile = File('${tempDir.path}/test_store.tmp');
      await dummyFile.writeAsBytes(Uint8List.fromList([1, 2, 3, 4, 5]));

      final memoryIndex = MemoryIndex(maxEntries: 10);
      final entry =
          createFileEntry(id: 'past_eof', fileOffset: 1000, fileLength: 50);
      memoryIndex.add(entry);

      final loader = DetailLoader(
        memoryIndex: memoryIndex,
        tempFilePathProvider: () => dummyFile.path,
        maxUiPreviewBytesProvider: () => 1024 * 1024,
      );

      final record = await loader.loadDetailByEntry(entry);
      expect(record.requestBodyPreview,
          equals(BodyDecodeService.unavailablePlaceholder));
      expect(record.responseBodyPreview,
          equals(BodyDecodeService.unavailablePlaceholder));
    });

    test('reading truncated file returns unavailable placeholder', () async {
      final dummyFile = File('${tempDir.path}/test_store.tmp');
      await dummyFile.writeAsBytes(Uint8List.fromList(List.filled(20, 0)));

      final memoryIndex = MemoryIndex(maxEntries: 10);
      final entry =
          createFileEntry(id: 'truncated', fileOffset: 0, fileLength: 200);
      memoryIndex.add(entry);

      final loader = DetailLoader(
        memoryIndex: memoryIndex,
        tempFilePathProvider: () => dummyFile.path,
        maxUiPreviewBytesProvider: () => 1024 * 1024,
      );

      final record = await loader.loadDetailByEntry(entry);
      expect(record.requestBodyPreview,
          equals(BodyDecodeService.unavailablePlaceholder));
      expect(record.responseBodyPreview,
          equals(BodyDecodeService.unavailablePlaceholder));
    });

    test(
        'reading rotated (emptied or recreated) file returns unavailable placeholder',
        () async {
      final dummyFile = File('${tempDir.path}/test_store.tmp');
      await dummyFile.writeAsBytes(Uint8List(0));

      final memoryIndex = MemoryIndex(maxEntries: 10);
      final entry =
          createFileEntry(id: 'rotated', fileOffset: 500, fileLength: 100);
      memoryIndex.add(entry);

      final loader = DetailLoader(
        memoryIndex: memoryIndex,
        tempFilePathProvider: () => dummyFile.path,
        maxUiPreviewBytesProvider: () => 1024 * 1024,
      );

      final record = await loader.loadDetailByEntry(entry);
      expect(record.requestBodyPreview,
          equals(BodyDecodeService.unavailablePlaceholder));
      expect(record.responseBodyPreview,
          equals(BodyDecodeService.unavailablePlaceholder));
    });

    test(
        'reading when temp file does not exist returns unavailable placeholder',
        () async {
      final memoryIndex = MemoryIndex(maxEntries: 10);
      final entry =
          createFileEntry(id: 'missing', fileOffset: 0, fileLength: 100);
      memoryIndex.add(entry);

      final loader = DetailLoader(
        memoryIndex: memoryIndex,
        tempFilePathProvider: () => '${tempDir.path}/non_existent_file.tmp',
        maxUiPreviewBytesProvider: () => 1024 * 1024,
      );

      final record = await loader.loadDetailByEntry(entry);
      expect(record.requestBodyPreview,
          equals(BodyDecodeService.unavailablePlaceholder));
      expect(record.responseBodyPreview,
          equals(BodyDecodeService.unavailablePlaceholder));
    });

    test(
        'end-to-end via InspectorSession when session file is purged or rotated',
        () async {
      final session = InspectorSession(
        settings: const InterceptlySettings(bodyOffloadThreshold: 50),
      );
      addTearDown(session.dispose);
      await session.initialize();

      final fakeEntry = createFileEntry(
          id: 'session_e2e_eof', fileOffset: 99999, fileLength: 500);
      final record = await session.loadDetail(fakeEntry);

      expect(record.requestBodyPreview,
          equals(BodyDecodeService.unavailablePlaceholder));
      expect(record.responseBodyPreview,
          equals(BodyDecodeService.unavailablePlaceholder));
    });
  });
}
