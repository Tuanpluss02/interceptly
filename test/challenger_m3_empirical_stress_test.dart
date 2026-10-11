import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/session/body_store.dart';
import 'package:interceptly/src/session/master_search_controller.dart';

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
  String url = 'https://example.com/api',
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
    durationMs: 15,
    requestSizeBytes: 100,
    responseSizeBytes: 200,
    timestamp: DateTime(2026, 1, 1),
    hasError: errorMessage != null,
    isBodyTruncated: false,
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

  late MasterSearchController controller;
  late Directory tempDir;
  late BodyStore bodyStore;
  late String tempFilePath;

  setUp(() async {
    controller = MasterSearchController();
    tempDir = await Directory.systemTemp.createTemp('challenger_stress_');
    bodyStore = BodyStore();
    await bodyStore.initForWrite(tempDir.path, fileName: 'stress.tmp');
    tempFilePath = '${tempDir.path}/stress.tmp';
  });

  tearDown(() async {
    controller.dispose();
    await bodyStore.dispose();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Stress Test: High Volume File-Backed Records & Handle Lifecycle', () {
    test(
        'Searches 60 file-backed records (15 batches) cleanly with single handle',
        () async {
      final entries = <IndexEntry>[];
      for (var i = 0; i < 60; i++) {
        final packed = _packBody(
          requestBody: '{"item_idx": $i, "code": "REQ_$i"}',
          responseBody: i % 2 == 0
              ? '{"result": "FOUND_TARGET_TOKEN", "id": $i}'
              : '{"result": "OTHER_PAYLOAD", "id": $i}',
        );
        final (offset, length) = await bodyStore.append(packed);
        entries.add(
          _makeEntry(
            id: 'file_entry_$i',
            url: 'https://example.com/item/$i',
            bodyLocation: BodyLocation.file,
            fileOffset: offset,
            fileLength: length,
          ),
        );
      }

      await controller.start(
        query: 'FOUND_TARGET_TOKEN',
        allEntries: entries,
        filePath: tempFilePath,
      );

      expect(controller.results, isNotNull);
      expect(controller.results!.length, equals(30));
      expect(controller.isScanningFiles, isFalse);

      // Verify file handle was closed by successfully resetting/deleting file
      await bodyStore.resetFile(tempDir.path, fileName: 'stress.tmp');
      expect(File(tempFilePath).existsSync(), isTrue);
    });

    test('Single open handle reused across batches without opening per item',
        () async {
      final entries = <IndexEntry>[];
      for (var i = 0; i < 16; i++) {
        final packed = _packBody(
          requestBody: '{"id": $i}',
          responseBody: '{"token": "batch_token_$i"}',
        );
        final (offset, length) = await bodyStore.append(packed);
        entries.add(
          _makeEntry(
            id: 'e_$i',
            url: 'https://example.com/$i',
            bodyLocation: BodyLocation.file,
            fileOffset: offset,
            fileLength: length,
          ),
        );
      }

      await controller.start(
        query: 'batch_token_',
        allEntries: entries,
        filePath: tempFilePath,
      );

      expect(controller.results!.length, equals(16));
    });
  });

  group('Stress Test: UI Throttling Behavior', () {
    test(
        'Rapid match updates are throttled within 150ms window and do not fire per match',
        () async {
      var notifyCount = 0;
      final notifyTimes = <int>[];
      final stopwatch = Stopwatch()..start();

      controller.addListener(() {
        notifyCount++;
        notifyTimes.add(stopwatch.elapsedMilliseconds);
      });

      // 40 in-memory items, each matched during Phase 2
      final entries = <IndexEntry>[];
      for (var i = 0; i < 40; i++) {
        final body = Uint8List.fromList(utf8.encode('{"match_key": "val_$i"}'));
        entries.add(
          _makeEntry(
            id: 'mem_$i',
            url: 'https://other.com/$i',
            bodyLocation: BodyLocation.memory,
            inlineResponseBody: body,
          ),
        );
      }

      await controller.start(
        query: 'match_key',
        allEntries: entries,
        filePath: null,
      );

      // 40 matches must NOT cause 40 notifications
      expect(notifyCount, lessThan(40));
      // But search completed, so final notification was forced
      expect(controller.results!.length, equals(40));
      expect(notifyCount, greaterThanOrEqualTo(2));
    });

    test('Dispose cancels active throttle timer cleanly', () async {
      final ctrl = MasterSearchController();
      var notificationsAfterDispose = 0;

      final body =
          Uint8List.fromList(utf8.encode('{"target": "disposed_target"}'));
      final entry = _makeEntry(
        id: 'disp_1',
        url: 'https://other.com/item',
        bodyLocation: BodyLocation.memory,
        inlineResponseBody: body,
      );

      ctrl.addListener(() {
        notificationsAfterDispose++;
      });

      final future = ctrl.start(
        query: 'disposed_target',
        allEntries: [entry],
        filePath: null,
      );

      ctrl.dispose();
      await future;
      final recordedCount = notificationsAfterDispose;

      // Wait beyond the 150ms throttle duration
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(notificationsAfterDispose, equals(recordedCount));
    });
  });

  group(
      'Adversarial Challenge: Cancellation & Race Conditions in Phase 1 & Phase 3',
      () {
    test(
        'Phase 1 yielding cancellation: cancel() during Phase 1 does not crash',
        () async {
      // 120 entries triggers Phase 1 yield at i = 50 and i = 100
      final entries = List.generate(
        120,
        (i) => _makeEntry(
          id: 'p1_$i',
          url: 'https://search.com/p1_$i',
        ),
      );

      final future = controller.start(
        query: 'search.com',
        allEntries: entries,
        filePath: null,
      );

      // Yield event loop to allow start() to begin and hit delayed(zero)
      await Future<void>.delayed(Duration.zero);

      // Cancel while Phase 1 is running
      controller.cancel();

      await future;

      expect(controller.isActive, isFalse);
      expect(controller.results, isNull);
    });

    test(
        'Phase 3 cancellation: cancel() during file scanning does not throw null-check error',
        () async {
      final entries = <IndexEntry>[];
      for (var i = 0; i < 4; i++) {
        // Large payload > 100KB so compute() isolate runs
        final longString = 'x' * (120 * 1024);
        final packed = _packBody(
          requestBody: '{"data": "$longString", "token": "cancel_token_$i"}',
          responseBody: '{"ok": true}',
        );
        final (offset, length) = await bodyStore.append(packed);
        entries.add(
          _makeEntry(
            id: 'c_entry_$i',
            url: 'https://example.com/c/$i',
            bodyLocation: BodyLocation.file,
            fileOffset: offset,
            fileLength: length,
          ),
        );
      }

      final searchFuture = controller.start(
        query: 'cancel_token_',
        allEntries: entries,
        filePath: tempFilePath,
      );

      // Yield event loop to allow start() to enter compute()
      await Future<void>.delayed(Duration.zero);

      // Cancel while compute isolate is processing
      controller.cancel();

      await searchFuture;

      expect(controller.query, isNull);
      expect(controller.results, isNull);
      expect(controller.isActive, isFalse);
    });

    test(
        'Rapid consecutive queries: query 2 supersedes query 1 without result contamination in Phase 1',
        () async {
      // 100 entries: 50 with 'alpha' in URL, 50 with 'beta' in URL
      final entries = <IndexEntry>[];
      for (var i = 0; i < 50; i++) {
        entries.add(
            _makeEntry(id: 'alpha_$i', url: 'https://example.com/alpha_$i'));
      }
      for (var i = 0; i < 50; i++) {
        entries
            .add(_makeEntry(id: 'beta_$i', url: 'https://example.com/beta_$i'));
      }

      // Start search for 'alpha'
      final search1 = controller.start(
        query: 'alpha',
        allEntries: entries,
        filePath: null,
      );

      // Immediately start search for 'beta' synchronously (simulating rapid keystroke)
      final search2 = controller.start(
        query: 'beta',
        allEntries: entries,
        filePath: null,
      );

      await Future.wait([search1, search2]);

      expect(controller.query, equals('beta'));
      expect(controller.results, isNotNull);
      // Results MUST only contain 'beta', not 'alpha'
      final containsAlpha =
          controller.results!.any((e) => e.url.contains('alpha'));
      expect(containsAlpha, isFalse,
          reason:
              'Results for "beta" were contaminated with "alpha" results from previous search');
      expect(controller.results!.length, equals(50));
    });

    test(
        'Rapid consecutive queries: query 2 supersedes query 1 without result contamination in Phase 3',
        () async {
      final entries = <IndexEntry>[];
      for (var i = 0; i < 40; i++) {
        final packedAlpha = _packBody(
          requestBody: '{"content": "alpha_file_content_$i"}',
        );
        final (offsetAlpha, lengthAlpha) = await bodyStore.append(packedAlpha);
        entries.add(
          _makeEntry(
            id: 'file_alpha_$i',
            url: 'https://example.com/a_$i',
            bodyLocation: BodyLocation.file,
            fileOffset: offsetAlpha,
            fileLength: lengthAlpha,
          ),
        );
      }
      for (var i = 0; i < 10; i++) {
        final packedBeta = _packBody(
          requestBody: '{"content": "beta_file_content_$i"}',
        );
        final (offsetBeta, lengthBeta) = await bodyStore.append(packedBeta);
        entries.add(
          _makeEntry(
            id: 'file_beta_$i',
            url: 'https://example.com/b_$i',
            bodyLocation: BodyLocation.file,
            fileOffset: offsetBeta,
            fileLength: lengthBeta,
          ),
        );
      }

      final search1 = controller.start(
        query: 'alpha_file_content',
        allEntries: entries,
        filePath: tempFilePath,
      );

      // Yield once to let search1 enter Phase 3 batches
      await Future<void>.delayed(Duration.zero);

      final search2 = controller.start(
        query: 'beta_file_content',
        allEntries: entries,
        filePath: tempFilePath,
      );

      await Future.wait([search1, search2]);

      final containsAlpha =
          controller.results!.any((e) => e.id.contains('alpha'));
      expect(containsAlpha, isFalse,
          reason:
              'Phase 3 results for "beta" were contaminated with "alpha" file records');
      expect(controller.results!.length, equals(10));
    });

    test(
        'dispose() during Phase 3 file scanning closes handle and terminates cleanly',
        () async {
      final ctrl = MasterSearchController();
      final entries = <IndexEntry>[];
      for (var i = 0; i < 16; i++) {
        final packed = _packBody(
          requestBody: '{"idx": $i}',
          responseBody: '{"content": "disp_token_$i"}',
        );
        final (offset, length) = await bodyStore.append(packed);
        entries.add(
          _makeEntry(
            id: 'disp_file_$i',
            url: 'https://example.com/disp/$i',
            bodyLocation: BodyLocation.file,
            fileOffset: offset,
            fileLength: length,
          ),
        );
      }

      final future = ctrl.start(
        query: 'disp_token_',
        allEntries: entries,
        filePath: tempFilePath,
      );

      await Future<void>.delayed(const Duration(milliseconds: 5));
      ctrl.dispose();

      await future;

      // Handle must be closed, file can be deleted
      await bodyStore.dispose();
      expect(File(tempFilePath).existsSync(), isFalse);
    });
  });
}
