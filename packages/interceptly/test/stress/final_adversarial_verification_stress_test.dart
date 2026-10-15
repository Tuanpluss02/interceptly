import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/export/curl_generator.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/request_record.dart';
import 'package:interceptly/src/session/body_store.dart';
import 'package:interceptly/src/session/master_search_controller.dart';
import 'package:interceptly/src/session/memory_index.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';

Uint8List _packBody({
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

IndexEntry _makeEntry({
  required String id,
  String method = 'GET',
  String url = 'https://api.example.com/data',
  BodyLocation bodyLocation = BodyLocation.memory,
  Uint8List? inlineRequestBody,
  Uint8List? inlineResponseBody,
  int? fileOffset,
  int? fileLength,
  Map<String, String> requestHeaders = const {},
  Map<String, String> responseHeaders = const {},
  String? errorMessage,
}) {
  return IndexEntry(
    id: id,
    method: method,
    url: url,
    statusCode: 200,
    durationMs: 25,
    requestSizeBytes: 120,
    responseSizeBytes: 240,
    timestamp: DateTime(2026, 1, 1),
    hasError: errorMessage != null,
    requestTruncation: const BodyTruncation.complete(0),
    responseTruncation: const BodyTruncation.complete(0),
    requestHeaders: requestHeaders,
    responseHeaders: responseHeaders,
    requestContentType: 'application/json',
    responseContentType: 'application/json',
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

  group('Milestone 4 Final Adversarial Verification Suite', () {
    test(
        'Vector 1: MemoryIndex massive concurrency flood and ring eviction integrity',
        () async {
      const capacity = 100;
      final index = MemoryIndex(maxEntries: capacity);

      const totalItems = 3000;
      final futures = <Future<void>>[];

      for (var chunk = 0; chunk < 10; chunk++) {
        final start = chunk * (totalItems ~/ 10);
        final end = start + (totalItems ~/ 10);
        futures.add(Future(() {
          for (var i = start; i < end; i++) {
            index.add(_makeEntry(
                id: 'req_$i', url: 'https://api.example.com/item/$i'));
          }
        }));
      }

      await Future.wait(futures);

      expect(index.entries.length, capacity);

      final newest = index.entries.first;
      expect(newest.id, startsWith('req_'));

      for (var i = 0; i < totalItems - capacity; i++) {
        expect(index.byId('req_$i'), isNull);
      }

      var retainedCount = 0;
      for (var i = totalItems - capacity; i < totalItems; i++) {
        if (index.byId('req_$i') != null) {
          retainedCount++;
        }
      }
      expect(retainedCount, capacity);

      for (var i = 0; i < capacity; i++) {
        final entry = index.entries[i];
        expect(index.byId(entry.id), isNotNull);
      }
    });

    test(
        'Vector 2: MasterSearchController extreme concurrent cancellations and disposed safety',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('m4_search_stress_');
      final sessionFile = File('${tempDir.path}/interceptly_session.tmp');
      final raf = await sessionFile.open(mode: FileMode.write);

      final entries = <IndexEntry>[];
      for (var i = 0; i < 120; i++) {
        final bodyBytes = _packBody(
          requestBody: '{"token": "secret_$i", "batch": "test"}',
          responseBody: '{"status": "ok", "index": $i, "keyword": "target_$i"}',
        );
        final offset = await raf.length();
        await raf.writeFrom(bodyBytes);
        entries.add(
          _makeEntry(
            id: 'file_entry_$i',
            url: 'https://api.example.com/record/$i',
            bodyLocation: BodyLocation.file,
            fileOffset: offset,
            fileLength: bodyBytes.length,
          ),
        );
      }
      await raf.close();

      final controller = MasterSearchController();

      final searchFutures = <Future<void>>[];
      for (var i = 0; i < 15; i++) {
        searchFutures.add(
          controller.start(
            query: 'target_$i',
            allEntries: entries,
            filePath: sessionFile.path,
          ),
        );
        if (i % 3 == 0) {
          controller.cancel();
        } else if (i % 3 == 1) {
          controller.reset();
        }
      }

      await Future.wait(searchFutures);

      await controller.start(
        query: 'target_50',
        allEntries: entries,
        filePath: sessionFile.path,
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(controller.results, isNotNull);
      expect(controller.results!.any((e) => e.id == 'file_entry_50'), isTrue);
      expect(controller.results!.every((e) => !e.id.contains('target_49')),
          isTrue);

      controller.dispose();

      expect(() => controller.cancel(), returnsNormally);
      expect(() => controller.reset(), returnsNormally);
      await controller.start(
        query: 'target_60',
        allEntries: entries,
        filePath: sessionFile.path,
      );
      expect(controller.results, anyOf(isNull, isEmpty));

      await tempDir.delete(recursive: true);
    });

    test(
        'Vector 3: High-Ceiling payload decoupling & cURL export integrity for > 2MB payloads',
        () {
      final largeBytes = Uint8List(3 * 1024 * 1024);
      for (var i = 0; i < 1000; i++) {
        largeBytes[i] = 65;
      }

      final record = RequestRecord(
        id: 'rec_large_1',
        url: 'https://api.example.com/upload',
        method: 'POST',
        statusCode: 200,
        durationMs: 120,
        requestSizeBytes: largeBytes.length,
        responseSizeBytes: largeBytes.length,
        timestamp: DateTime(2026, 1, 1),
        requestHeaders: {
          'content-type': 'application/octet-stream',
          'Authorization': 'Bearer 12345'
        },
        responseHeaders: {'content-type': 'application/json'},
        requestBodyBytes: largeBytes,
        requestBodyPreview: 'A' * 2048,
        responseBodyBytes: largeBytes,
        responseBodyPreview: 'Preview truncated',
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation(
          originalBytes: 7000000,
          retainedBytes: 2000000,
          stage: TruncationStage.preview,
        ),
      );

      expect(record.requestBodyBytes?.length, 3 * 1024 * 1024);
      expect(record.responseBodyBytes?.length, 3 * 1024 * 1024);
      expect(record.hasDataLoss, isFalse);
      expect(record.responseTruncation.isPreviewOnly, isTrue);

      final curl = CurlGenerator.fromRecord(record);
      expect(curl, contains('curl'));
      expect(curl, contains('https://api.example.com/upload'));
      expect(curl, contains("-X 'POST'"));
    });

    testWidgets('Vector 4: JsonViewer virtualization with 30,000 lines payload',
        (tester) async {
      final sb = StringBuffer('{\n');
      for (var i = 0; i < 30000; i++) {
        sb.write('  "key_$i": "value_$i",\n');
      }
      sb.write('  "end": true\n}');
      final largeJson = sb.toString();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              width: 800,
              child: JsonViewer(
                data: largeJson,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final listViews = find.byType(ListView);
      expect(listViews, findsAtLeastNWidgets(1));

      final firstListView = tester.widget<ListView>(listViews.first);
      expect(firstListView.itemExtent, 18.0);
    });

    test(
        'Vector 5: Temp file cleanup robustness with nested directories and non-orphan files',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('m4_cleanup_stress_');

      final activeFile = File('${tempDir.path}/interceptly_active.tmp');
      await activeFile.writeAsString('active session content');

      final orphan1 = File('${tempDir.path}/interceptly_orphan1.tmp');
      await orphan1.writeAsString('orphan 1 content');

      final orphan2 = File('${tempDir.path}/interceptly_orphan2.tmp');
      await orphan2.writeAsString('orphan 2 content');

      final otherFile = File('${tempDir.path}/unrelated_file.txt');
      await otherFile.writeAsString('do not delete');

      final notTmpFile = File('${tempDir.path}/interceptly_not_tmp.log');
      await notTmpFile.writeAsString('keep log');

      final nestedDir = Directory('${tempDir.path}/interceptly_nested.tmp');
      await nestedDir.create();
      final nestedFile = File('${nestedDir.path}/inner.txt');
      await nestedFile.writeAsString('inside dir');

      final purged = await BodyStore.purgeOrphanedTempFiles(
        tempDir.path,
        currentFileName: 'interceptly_active.tmp',
      );

      expect(purged, 2);
      expect(await activeFile.exists(), isTrue);
      expect(await orphan1.exists(), isFalse);
      expect(await orphan2.exists(), isFalse);
      expect(await otherFile.exists(), isTrue);
      expect(await notTmpFile.exists(), isTrue);
      expect(await nestedDir.exists(), isTrue);
      expect(await nestedFile.exists(), isTrue);

      await tempDir.delete(recursive: true);
    });
  });
}
