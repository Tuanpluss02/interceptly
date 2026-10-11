import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/session/body_store.dart';
import 'package:interceptly/src/session/master_search_controller.dart';

Uint8List _packBody({
  String? requestBody,
  String? responseBody,
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

  out[offset] = 0;
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
    tempDir = await Directory.systemTemp.createTemp('deep_stress_');
    bodyStore = BodyStore();
    await bodyStore.initForWrite(tempDir.path, fileName: 'deep_stress.tmp');
    tempFilePath = '${tempDir.path}/deep_stress.tmp';
  });

  tearDown(() async {
    controller.dispose();
    await bodyStore.dispose();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Deep Empirical Stress: Phase 1 Yielding & Cancellation Race Conditions', () {
    test('Cancel during every Phase 1 yield iteration (i=0, 50, 100, 150) never crashes', () async {
      final entries = List.generate(
        200,
        (i) => _makeEntry(
          id: 'yield_target_$i',
          url: 'https://example.com/item_$i',
          requestHeaders: {'x-tag': 'yield_target_$i'},
        ),
      );

      for (var delayTicks = 0; delayTicks < 5; delayTicks++) {
        final ctrl = MasterSearchController();
        final searchFuture = ctrl.start(
          query: 'yield_target',
          allEntries: entries,
          filePath: null,
        );

        for (var d = 0; d < delayTicks; d++) {
          await Future<void>.delayed(Duration.zero);
        }

        ctrl.cancel();
        await searchFuture;

        expect(ctrl.isActive, isFalse);
        expect(ctrl.query, isNull);
        expect(ctrl.results, isNull);
        ctrl.dispose();
      }
    });

    test('Reset during Phase 1 yield cleanly aborts and leaves null results', () async {
      final entries = List.generate(
        150,
        (i) => _makeEntry(id: 'reset_$i', url: 'https://example.com/reset_$i'),
      );

      final searchFuture = controller.start(
        query: 'reset_',
        allEntries: entries,
        filePath: null,
      );

      await Future<void>.delayed(Duration.zero);
      controller.reset();
      await searchFuture;

      expect(controller.isActive, isFalse);
      expect(controller.query, isNull);
      expect(controller.results, isNull);
    });
  });

  group('Deep Empirical Stress: Rapid Keystroke Barrage & Cross-Contamination Oracle', () {
    test('10 rapid consecutive queries supersede each other without cross-contamination in Phase 1', () async {
      final categories = [
        'apple',
        'banana',
        'cherry',
        'durian',
        'elderberry',
        'fig',
        'grape',
        'honeydew',
        'kiwi',
        'lemon',
      ];

      final entries = <IndexEntry>[];
      for (final cat in categories) {
        for (var i = 0; i < 20; i++) {
          entries.add(_makeEntry(
            id: '${cat}_$i',
            url: 'https://fruits.com/catalog/${cat}_$i',
          ));
        }
      }

      final futures = <Future<void>>[];
      for (final cat in categories) {
        futures.add(controller.start(
          query: cat,
          allEntries: entries,
          filePath: null,
        ));
      }

      await Future.wait(futures);

      expect(controller.query, equals('lemon'));
      expect(controller.results, isNotNull);
      expect(controller.results!.length, equals(20));

      for (final r in controller.results!) {
        expect(r.url, contains('lemon'));
        for (final other in categories.where((c) => c != 'lemon')) {
          expect(r.url.contains(other), isFalse,
              reason: 'Found contaminated result from previous query $other in lemon results');
        }
      }
    });

    test('Barrage of 20 rapid interleaved queries across Phase 1, Phase 2, and Phase 3', () async {
      final entries = <IndexEntry>[];

      for (var i = 0; i < 15; i++) {
        final packed = _packBody(
          requestBody: '{"content": "file_needle_$i"}',
        );
        final (offset, length) = await bodyStore.append(packed);
        entries.add(
          _makeEntry(
            id: 'file_entry_$i',
            url: 'https://example.com/file/$i',
            bodyLocation: BodyLocation.file,
            fileOffset: offset,
            fileLength: length,
          ),
        );
      }

      for (var i = 0; i < 20; i++) {
        entries.add(_makeEntry(
          id: 'mem_entry_$i',
          url: 'https://example.com/mem/$i',
          bodyLocation: BodyLocation.memory,
          inlineResponseBody: Uint8List.fromList(utf8.encode('{"note": "mem_needle_$i"}')),
        ));
      }

      for (var i = 0; i < 30; i++) {
        entries.add(_makeEntry(
          id: 'struct_entry_$i',
          url: 'https://example.com/struct/struct_needle_$i',
        ));
      }

      final querySequence = [
        'struct_needle',
        'mem_needle',
        'file_needle',
        'struct_needle_1',
        'mem_needle_2',
        'file_needle_3',
        'non_existent_token_12345',
      ];

      for (final q in querySequence) {
        controller.start(
          query: q,
          allEntries: entries,
          filePath: tempFilePath,
        );
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      await controller.start(
        query: 'file_needle_0',
        allEntries: entries,
        filePath: tempFilePath,
      );

      expect(controller.query, equals('file_needle_0'));
      expect(controller.results, isNotNull);
      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('file_entry_0'));
    });
  });

  group('Deep Empirical Stress: Randomized Concurrency Torture Harness', () {
    test('50 randomized concurrent operations (start, cancel, reset) maintain invariant integrity', () async {
      final rng = Random(42);
      final entries = List.generate(
        80,
        (i) => _makeEntry(
          id: 'torture_$i',
          url: 'https://api.test/torture_$i',
          inlineResponseBody: Uint8List.fromList(utf8.encode('{"idx": $i}')),
        ),
      );

      for (var step = 0; step < 50; step++) {
        final action = rng.nextInt(3);
        if (action == 0) {
          final queryIdx = rng.nextInt(80);
          controller.start(
            query: 'torture_$queryIdx',
            allEntries: entries,
            filePath: null,
          );
        } else if (action == 1) {
          controller.cancel();
        } else {
          controller.reset();
        }

        if (rng.nextBool()) {
          await Future<void>.delayed(Duration(microseconds: rng.nextInt(500)));
        }
      }

      await controller.start(
        query: 'torture_42',
        allEntries: entries,
        filePath: null,
      );

      expect(controller.isActive, isTrue);
      expect(controller.query, equals('torture_42'));
      expect(controller.results, isNotNull);
      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('torture_42'));
    });
  });
}
