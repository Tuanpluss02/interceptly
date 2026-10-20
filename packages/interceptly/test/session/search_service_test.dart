// ignore_for_file: invalid_use_of_internal_member
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/engine/body_decode_service.dart';
import 'package:interceptly/src/engine/body_store.dart';
import 'package:interceptly/src/engine/search_service.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/search_match_scope.dart';

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

IndexEntry _buildEntry({
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
  String? errorType,
  BodyLocation bodyLocation = BodyLocation.memory,
  Uint8List? inlineRequestBody,
  Uint8List? inlineResponseBody,
  int? fileOffset,
  int? fileLength,
  int? fileRotationCount,
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
    errorType: errorType,
    bodyLocation: bodyLocation,
    inlineRequestBody: inlineRequestBody,
    inlineResponseBody: inlineResponseBody,
    fileOffset: fileOffset,
    fileLength: fileLength,
    fileRotationCount: fileRotationCount,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BodyStore bodyStore;
  late String tempFilePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('search_service_test_');
    bodyStore = BodyStore();
    await bodyStore.initForWrite(tempDir.path, fileName: 'search_session.tmp');
    tempFilePath = '${tempDir.path}/search_session.tmp';
  });

  tearDown(() async {
    await bodyStore.dispose();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SearchService: Metadata matching with scope tagging', () {
    test(
        'matches URL, HTTP method, error details, and headers with correct scopes',
        () async {
      final e1 = _buildEntry(
        id: '1',
        method: 'POST',
        url: 'https://api.example.com/checkout/orders',
      );
      final e2 = _buildEntry(
        id: '2',
        method: 'DELETE',
        url: 'https://api.example.com/users/99',
      );
      final e3 = _buildEntry(
        id: '3',
        requestHeaders: {'x-custom-tenant': 'acme-corp-42'},
      );
      final e4 = _buildEntry(
        id: '4',
        responseHeaders: {
          'content-disposition': 'attachment; filename=report.pdf'
        },
      );
      final e5 = _buildEntry(
        id: '5',
        hasError: true,
        errorMessage: 'Connection timed out while connecting',
        errorType: 'SocketException',
      );

      final entries = [e1, e2, e3, e4, e5];

      final resUrl =
          await SearchService.search(entries: entries, query: 'checkout');
      expect(resUrl.length, 1);
      expect(resUrl.first.summary.id, '1');
      expect(resUrl.first.matchScopes, contains(SearchMatchScope.url));

      final resMethod =
          await SearchService.search(entries: entries, query: 'delete');
      expect(resMethod.length, 1);
      expect(resMethod.first.summary.id, '2');
      expect(resMethod.first.matchScopes, contains(SearchMatchScope.url));

      final resReqHeader =
          await SearchService.search(entries: entries, query: 'acme-corp');
      expect(resReqHeader.length, 1);
      expect(resReqHeader.first.summary.id, '3');
      expect(
          resReqHeader.first.matchScopes, contains(SearchMatchScope.headers));

      final resResHeader =
          await SearchService.search(entries: entries, query: 'report.pdf');
      expect(resResHeader.length, 1);
      expect(resResHeader.first.summary.id, '4');
      expect(
          resResHeader.first.matchScopes, contains(SearchMatchScope.headers));

      final resError = await SearchService.search(
          entries: entries, query: 'socketexception');
      expect(resError.length, 1);
      expect(resError.first.summary.id, '5');
      expect(resError.first.matchScopes, contains(SearchMatchScope.error));
    });

    test('treats regex metacharacters as literal substrings', () async {
      final e1 = _buildEntry(
          id: '1', url: 'https://api.example.com/test?filter=.*&tag=[a-z]');
      final e2 = _buildEntry(
          id: '2', url: 'https://api.example.com/test?filter=normal');

      final res = await SearchService.search(
        entries: [e1, e2],
        query: '.*&tag=[a-z]',
      );

      expect(res.length, 1);
      expect(res.first.summary.id, '1');
    });

    test('returns empty results on empty query or empty entries', () async {
      final e1 = _buildEntry(id: '1', url: 'https://api.example.com/test');

      expect(await SearchService.search(entries: [e1], query: ''), isEmpty);
      expect(await SearchService.search(entries: [e1], query: '   '), isEmpty);
      expect(await SearchService.search(entries: [], query: 'test'), isEmpty);
    });
  });

  group('SearchService: Binary guard', () {
    test(
        'skips body scanning if response is binary even when request is empty/null',
        () async {
      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);
      final e = _buildEntry(
        id: 'binary_1',
        url: 'https://cdn.example.com/item/12345',
        requestSizeBytes: 0,
        requestContentType: null,
        responseSizeBytes: pngBytes.length,
        responseContentType: 'image/png',
        inlineResponseBody: pngBytes,
      );

      final res = await SearchService.search(
        entries: [e],
        query: 'PNG',
        searchBody: true,
      );
      expect(res, isEmpty);
    });

    test('skips body scanning if request is binary and response is empty',
        () async {
      final pdfBytes = Uint8List.fromList(utf8.encode('%PDF-1.4 file content'));
      final e = _buildEntry(
        id: 'binary_2',
        url: 'https://cdn.example.com/upload',
        requestSizeBytes: pdfBytes.length,
        requestContentType: 'application/pdf',
        inlineRequestBody: pdfBytes,
        responseSizeBytes: 0,
        responseContentType: null,
      );

      final res = await SearchService.search(
        entries: [e],
        query: 'PDF',
        searchBody: true,
      );
      expect(res, isEmpty);
    });
  });

  group('SearchService: In-memory body search', () {
    test('matches in-memory request and response body text', () async {
      final reqBytes =
          Uint8List.fromList(utf8.encode('{"query": "find_alice"}'));
      final resBytes =
          Uint8List.fromList(utf8.encode('{"status": "found_bob"}'));

      final e1 = _buildEntry(
        id: 'mem_1',
        inlineRequestBody: reqBytes,
      );
      final e2 = _buildEntry(
        id: 'mem_2',
        inlineResponseBody: resBytes,
      );

      final res1 =
          await SearchService.search(entries: [e1, e2], query: 'find_alice');
      expect(res1.length, 1);
      expect(res1.first.summary.id, 'mem_1');
      expect(res1.first.matchScopes, contains(SearchMatchScope.body));

      final res2 =
          await SearchService.search(entries: [e1, e2], query: 'found_bob');
      expect(res2.length, 1);
      expect(res2.first.summary.id, 'mem_2');
      expect(res2.first.matchScopes, contains(SearchMatchScope.body));
    });

    test('supports unicode, accents, and emojis in body search', () async {
      final bodyBytes = Uint8List.fromList(
        utf8.encode('{"greeting": "Xin chào thế giới 🚀"}'),
      );
      final e = _buildEntry(
        id: 'unicode_1',
        inlineResponseBody: bodyBytes,
      );

      final resAccents =
          await SearchService.search(entries: [e], query: 'chào');
      expect(resAccents.length, 1);
      expect(resAccents.first.summary.id, 'unicode_1');

      final resEmoji = await SearchService.search(entries: [e], query: '🚀');
      expect(resEmoji.length, 1);
      expect(resEmoji.first.summary.id, 'unicode_1');
    });

    test('skips Phase 2 and Phase 3 when searchBody is false', () async {
      final bodyBytes =
          Uint8List.fromList(utf8.encode('{"token": "secret_abc"}'));
      final e = _buildEntry(
        id: 'skip_body',
        url: 'https://api.example.com/unrelated',
        inlineResponseBody: bodyBytes,
      );

      final resOff = await SearchService.search(
        entries: [e],
        query: 'secret_abc',
        searchBody: false,
      );
      expect(resOff, isEmpty);

      final resOn = await SearchService.search(
        entries: [e],
        query: 'secret_abc',
        searchBody: true,
      );
      expect(resOn.length, 1);
    });
  });

  group('SearchService: File-backed search, batching, and handle safety', () {
    test('reads and matches file-backed request and response bodies from disk',
        () async {
      final packed1 = _createPackedBody(
        requestBody: '{"action": "submit_order", "secretCode": "ALPHA_42"}',
        responseBody: '{"status": "ok"}',
      );
      final (offset1, length1) = await bodyStore.append(packed1);

      final packed2 = _createPackedBody(
        requestBody: '{"action": "ping"}',
        responseBody: '{"message": "pong_service_online"}',
      );
      final (offset2, length2) = await bodyStore.append(packed2);

      final e1 = _buildEntry(
        id: 'file_1',
        bodyLocation: BodyLocation.file,
        fileOffset: offset1,
        fileLength: length1,
      );
      final e2 = _buildEntry(
        id: 'file_2',
        bodyLocation: BodyLocation.file,
        fileOffset: offset2,
        fileLength: length2,
      );

      final res1 = await SearchService.search(
        entries: [e1, e2],
        query: 'ALPHA_42',
        filePath: tempFilePath,
      );
      expect(res1.length, 1);
      expect(res1.first.summary.id, 'file_1');
      expect(res1.first.matchScopes, contains(SearchMatchScope.body));

      final res2 = await SearchService.search(
        entries: [e1, e2],
        query: 'pong_service',
        filePath: tempFilePath,
      );
      expect(res2.length, 1);
      expect(res2.first.summary.id, 'file_2');
      expect(res2.first.matchScopes, contains(SearchMatchScope.body));
    });

    test('processes file entries in batches (>16 entries)', () async {
      final entries = <IndexEntry>[];
      for (var i = 0; i < 20; i++) {
        final packed = _createPackedBody(
          requestBody: '{"batchIndex": $i}',
          responseBody: '{"data": "batch_token_$i"}',
        );
        final (offset, length) = await bodyStore.append(packed);
        entries.add(_buildEntry(
          id: 'batch_file_$i',
          bodyLocation: BodyLocation.file,
          fileOffset: offset,
          fileLength: length,
        ));
      }

      final res = await SearchService.search(
        entries: entries,
        query: 'batch_token_',
        filePath: tempFilePath,
      );
      expect(res.length, 20);
    });

    test(
        'offloads large bodies (>100KB) to background isolate unpack without failure',
        () async {
      final largePayload = 'A' * (BodyDecodeService.computeThreshold + 1024);
      final packed = _createPackedBody(
        requestBody:
            '{"large": "$largePayload", "needle": "target_isolate_data"}',
      );
      final (offset, length) = await bodyStore.append(packed);

      final e = _buildEntry(
        id: 'large_entry',
        bodyLocation: BodyLocation.file,
        fileOffset: offset,
        fileLength: length,
      );

      final res = await SearchService.search(
        entries: [e],
        query: 'target_isolate_data',
        filePath: tempFilePath,
      );
      expect(res.length, 1);
      expect(res.first.summary.id, 'large_entry');
    });

    test('skips entries expired by file rotation count', () async {
      final packed =
          _createPackedBody(requestBody: '{"data": "old_generation"}');
      final (offset, length) = await bodyStore.append(packed);

      final expiredEntry = _buildEntry(
        id: 'expired_1',
        bodyLocation: BodyLocation.file,
        fileOffset: offset,
        fileLength: length,
        fileRotationCount: 1,
      );

      final res = await SearchService.search(
        entries: [expiredEntry],
        query: 'old_generation',
        filePath: tempFilePath,
        fileRotationCount: 2,
      );
      expect(res, isEmpty);
    });

    test('gracefully handles missing file or invalid offsets without throwing',
        () async {
      final corrupted = _buildEntry(
        id: 'corrupted_1',
        bodyLocation: BodyLocation.file,
        fileOffset: 9999999,
        fileLength: 5000,
      );

      final resCorrupted = await SearchService.search(
        entries: [corrupted],
        query: 'anything',
        filePath: tempFilePath,
      );
      expect(resCorrupted, isEmpty);

      final resMissing = await SearchService.search(
        entries: [corrupted],
        query: 'anything',
        filePath: '${tempDir.path}/non_existent_file.tmp',
      );
      expect(resMissing, isEmpty);
    });
  });

  group('SearchService: Status filter, cursor pagination, and limit', () {
    test('filters by status: 2xx, 3xx, 4xx, 5xx, failed, and all', () async {
      final entries = [
        _buildEntry(id: 'e200', statusCode: 200),
        _buildEntry(id: 'e204', statusCode: 204),
        _buildEntry(id: 'e302', statusCode: 302),
        _buildEntry(id: 'e404', statusCode: 404),
        _buildEntry(id: 'e500', statusCode: 500),
        _buildEntry(id: 'eErr', statusCode: 200, hasError: true),
      ];

      final res2xx = await SearchService.search(
        entries: entries,
        query: 'items',
        statusFilter: '2xx',
      );
      expect(res2xx.map((r) => r.summary.id), containsAll(['e200', 'e204']));
      expect(res2xx.any((r) => r.summary.statusCode >= 300), isFalse);

      final res3xx = await SearchService.search(
        entries: entries,
        query: 'items',
        statusFilter: '3xx',
      );
      expect(res3xx.map((r) => r.summary.id), ['e302']);

      final res4xx = await SearchService.search(
        entries: entries,
        query: 'items',
        statusFilter: '4xx',
      );
      expect(res4xx.map((r) => r.summary.id), ['e404']);

      final res5xx = await SearchService.search(
        entries: entries,
        query: 'items',
        statusFilter: '5xx',
      );
      expect(res5xx.map((r) => r.summary.id), ['e500']);

      final resFailed = await SearchService.search(
        entries: entries,
        query: 'items',
        statusFilter: 'failed',
      );
      expect(resFailed.map((r) => r.summary.id),
          containsAll(['e404', 'e500', 'eErr']));
    });

    test('supports sinceId cursor pagination and limit cap', () async {
      final entries = List.generate(
        10,
        (i) => _buildEntry(
          id: '${10 - i}',
          url: 'https://api.example.com/record_${10 - i}',
        ),
      );

      final resLimit = await SearchService.search(
        entries: entries,
        query: 'record_',
        limit: 3,
      );
      expect(resLimit.length, 3);
      expect(resLimit.map((r) => r.summary.id).toList(), ['10', '9', '8']);

      final resSince = await SearchService.search(
        entries: entries,
        query: 'record_',
        sinceId: '8',
      );
      expect(resSince.map((r) => r.summary.id).toList(), ['10', '9']);

      final resSinceNewest = await SearchService.search(
        entries: entries,
        query: 'record_',
        sinceId: '10',
      );
      expect(resSinceNewest, isEmpty);
    });
  });

  group('SearchService: Progressive callback and cancellation', () {
    test('emits progressive results and terminates with isDone: true',
        () async {
      final entryMem = _buildEntry(
        id: 'mem_1',
        url: 'https://api.example.com/other',
        bodyLocation: BodyLocation.memory,
        inlineResponseBody:
            Uint8List.fromList(utf8.encode('{"key": "prog_match"}')),
      );

      final packed = _createPackedBody(
        requestBody: '{"key": "prog_match"}',
      );
      final (offset, length) = await bodyStore.append(packed);
      final entryFile = _buildEntry(
        id: 'file_1',
        url: 'https://api.example.com/other',
        bodyLocation: BodyLocation.file,
        fileOffset: offset,
        fileLength: length,
      );

      final progressEvents = <(int, bool)>[];
      final phases = <SearchPhase>[];

      final results = await SearchService.search(
        entries: [entryMem, entryFile],
        query: 'prog_match',
        filePath: tempFilePath,
        onProgress: (progressiveResults, {required bool isDone}) {
          progressEvents.add((progressiveResults.length, isDone));
        },
        onPhaseChange: (phase) {
          phases.add(phase);
        },
      );

      expect(results.length, 2);
      expect(progressEvents, isNotEmpty);
      expect(progressEvents.last.$2, isTrue);
      expect(phases, contains(SearchPhase.metadata));
      expect(phases, contains(SearchPhase.inMemoryBodies));
      expect(phases, contains(SearchPhase.fileBodies));
      expect(phases.last, equals(SearchPhase.done));
    });

    test('aborts promptly when isCancelled returns true', () async {
      final entries = List.generate(
        30,
        (i) => _buildEntry(
          id: 'entry_$i',
          url: 'https://api.example.com/test_$i',
        ),
      );

      var checkCount = 0;
      final results = await SearchService.search(
        entries: entries,
        query: 'test_',
        isCancelled: () {
          checkCount++;
          return checkCount >= 2;
        },
      );

      expect(results, isEmpty);
    });
  });

  group('SearchService.matchEntry: Single entry dynamic matching', () {
    test('matches structured metadata scopes and returns SearchResult', () {
      final entry = _buildEntry(
        id: 'dyn_1',
        method: 'POST',
        url: 'https://api.example.com/checkout',
      );

      final match = SearchService.matchEntry(entry, 'checkout');
      expect(match, isNotNull);
      expect(match!.summary.id, 'dyn_1');
      expect(match.matchScopes, contains(SearchMatchScope.url));
    });

    test('matches inline memory body and tags body scope', () {
      final entry = _buildEntry(
        id: 'dyn_2',
        bodyLocation: BodyLocation.memory,
        inlineResponseBody:
            Uint8List.fromList(utf8.encode('{"orderId": "ORD_999"}')),
      );

      final match = SearchService.matchEntry(entry, 'ord_999');
      expect(match, isNotNull);
      expect(match!.summary.id, 'dyn_2');
      expect(match.matchScopes, contains(SearchMatchScope.body));
    });

    test('returns null when entry does not match query', () {
      final entry = _buildEntry(
        id: 'dyn_3',
        url: 'https://api.example.com/hello',
      );

      final match = SearchService.matchEntry(entry, 'goodbye');
      expect(match, isNull);
    });

    test('respects searchBody: false for inline body matching', () {
      final entry = _buildEntry(
        id: 'dyn_4',
        url: 'https://api.example.com/items',
        bodyLocation: BodyLocation.memory,
        inlineResponseBody:
            Uint8List.fromList(utf8.encode('{"secret": "xyz"}')),
      );

      final matchWithSearchBodyFalse = SearchService.matchEntry(
        entry,
        'xyz',
        searchBody: false,
      );
      expect(matchWithSearchBodyFalse, isNull);

      final matchWithSearchBodyTrue = SearchService.matchEntry(
        entry,
        'xyz',
        searchBody: true,
      );
      expect(matchWithSearchBodyTrue, isNotNull);
    });

    test('applies binary guard to inline body in matchEntry', () {
      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);
      final entry = _buildEntry(
        id: 'dyn_5',
        url: 'https://cdn.example.com/item/12345',
        requestSizeBytes: 0,
        requestContentType: null,
        responseSizeBytes: pngBytes.length,
        responseContentType: 'image/png',
        inlineResponseBody: pngBytes,
      );

      final match = SearchService.matchEntry(entry, 'PNG');
      expect(match, isNull);
    });
  });
}
