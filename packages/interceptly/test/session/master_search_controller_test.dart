// ignore_for_file: invalid_use_of_internal_member
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/search_match_scope.dart';
import 'package:interceptly/src/engine/body_store.dart';
import 'package:interceptly/src/engine/master_search_controller.dart';

/// Helper to create a packed body buffer compatible with BodyDecodeService.
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

/// Factory for building test IndexEntry instances.
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

  late MasterSearchController controller;
  late Directory tempDir;
  late BodyStore bodyStore;
  late String tempFilePath;

  setUp(() async {
    controller = MasterSearchController();
    tempDir = await Directory.systemTemp.createTemp('master_search_test_');
    bodyStore = BodyStore();
    await bodyStore.initForWrite(tempDir.path, fileName: 'search_session.tmp');
    tempFilePath = '${tempDir.path}/search_session.tmp';
  });

  tearDown(() async {
    controller.dispose();
    await bodyStore.dispose();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MasterSearchController: Initial State & Basic Lifecycle', () {
    test('Default uninitialized controller state', () {
      expect(controller.query, isNull);
      expect(controller.results, isNull);
      expect(controller.isActive, isFalse);
      expect(controller.isScanningBodies, isFalse);
      expect(controller.isScanningFiles, isFalse);
    });

    test('cancel() resets query, results and notifies listeners', () async {
      var notified = false;
      controller.addListener(() => notified = true);

      final entry =
          _buildEntry(id: 'entry-1', url: 'https://api.example.com/users');
      await controller.start(
        query: 'users',
        allEntries: [entry],
        filePath: null,
      );

      expect(controller.isActive, isTrue);
      expect(controller.results, isNotEmpty);

      notified = false;
      controller.cancel();

      expect(notified, isTrue);
      expect(controller.query, isNull);
      expect(controller.results, isNull);
      expect(controller.isActive, isFalse);
    });

    test('reset() resets query and results without notifying listeners',
        () async {
      final entry =
          _buildEntry(id: 'entry-2', url: 'https://api.example.com/orders');
      await controller.start(
        query: 'orders',
        allEntries: [entry],
        filePath: null,
      );

      var notified = false;
      controller.addListener(() => notified = true);

      controller.reset();

      expect(notified, isFalse);
      expect(controller.query, isNull);
      expect(controller.results, isNull);
      expect(controller.isActive, isFalse);
    });

    test('Empty or whitespace query cancels search immediately', () async {
      final entry =
          _buildEntry(id: 'entry-3', url: 'https://api.example.com/items');
      await controller.start(
        query: '   ',
        allEntries: [entry],
        filePath: null,
      );

      expect(controller.query, isNull);
      expect(controller.results, isNull);
      expect(controller.isActive, isFalse);
    });
  });

  group('MasterSearchController: Phase 1 Structured Fields', () {
    test('Matches URL case-insensitively and returns matching entry', () async {
      final e1 =
          _buildEntry(id: 'e1', url: 'https://checkout.stripe.com/v1/pay');
      final e2 = _buildEntry(id: 'e2', url: 'https://api.github.com/repos');

      await controller.start(
        query: 'STRIPE',
        allEntries: [e1, e2],
        filePath: null,
      );

      expect(controller.results, isNotNull);
      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('e1'));
    });

    test('Matches HTTP method substring', () async {
      final e1 = _buildEntry(id: 'e1', method: 'DELETE');
      final e2 = _buildEntry(id: 'e2', method: 'POST');

      await controller.start(
        query: 'dele',
        allEntries: [e1, e2],
        filePath: null,
      );

      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('e1'));
    });

    test('Matches request and response header keys and values', () async {
      final e1 = _buildEntry(
        id: 'e1',
        requestHeaders: {'x-custom-tenant': 'acme-corp'},
      );
      final e2 = _buildEntry(
        id: 'e2',
        responseHeaders: {
          'content-disposition': 'attachment; filename=report.pdf'
        },
      );
      final e3 = _buildEntry(id: 'e3');

      await controller.start(
        query: 'acme-corp',
        allEntries: [e1, e2, e3],
        filePath: null,
      );
      expect(controller.results!.map((e) => e.id), contains('e1'));

      await controller.start(
        query: 'report.pdf',
        allEntries: [e1, e2, e3],
        filePath: null,
      );
      expect(controller.results!.map((e) => e.id), contains('e2'));
    });

    test('Matches error message string', () async {
      final e1 = _buildEntry(
        id: 'e1',
        hasError: true,
        errorMessage: 'Connection reset by peer',
      );
      final e2 = _buildEntry(id: 'e2');

      await controller.start(
        query: 'reset by peer',
        allEntries: [e1, e2],
        filePath: null,
      );

      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('e1'));
    });
  });

  group('MasterSearchController: Phase 2 In-Memory Body Search', () {
    test('Matches in-memory request body bytes', () async {
      final bodyBytes = Uint8List.fromList(
          utf8.encode('{"customerEmail": "john.doe@example.com"}'));
      final e1 = _buildEntry(
        id: 'e1',
        bodyLocation: BodyLocation.memory,
        inlineRequestBody: bodyBytes,
      );
      final e2 = _buildEntry(id: 'e2', bodyLocation: BodyLocation.memory);

      await controller.start(
        query: 'john.doe',
        allEntries: [e1, e2],
        filePath: null,
      );

      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('e1'));
    });

    test('Matches in-memory response body bytes', () async {
      final bodyBytes =
          Uint8List.fromList(utf8.encode('{"transactionId": "tx_987654321"}'));
      final e1 = _buildEntry(
        id: 'e1',
        bodyLocation: BodyLocation.memory,
        inlineResponseBody: bodyBytes,
      );
      final e2 = _buildEntry(id: 'e2', bodyLocation: BodyLocation.memory);

      await controller.start(
        query: 'tx_987654321',
        allEntries: [e1, e2],
        filePath: null,
      );

      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('e1'));
    });
  });

  group('MasterSearchController: Phase 3 File-Backed Body Search', () {
    test('Matches file-backed request and response bodies from disk', () async {
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
        id: 'e1',
        bodyLocation: BodyLocation.file,
        fileOffset: offset1,
        fileLength: length1,
      );
      final e2 = _buildEntry(
        id: 'e2',
        bodyLocation: BodyLocation.file,
        fileOffset: offset2,
        fileLength: length2,
      );

      await controller.start(
        query: 'ALPHA_42',
        allEntries: [e1, e2],
        filePath: tempFilePath,
      );
      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('e1'));

      await controller.start(
        query: 'pong_service',
        allEntries: [e1, e2],
        filePath: tempFilePath,
      );
      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('e2'));
    });

    test('Deduplicates results when entry matches Phase 1 and file body',
        () async {
      final packed = _createPackedBody(
        requestBody: '{"product": "keyboard"}',
        responseBody: '{"status": "in_stock"}',
      );
      final (offset, length) = await bodyStore.append(packed);

      final e1 = _buildEntry(
        id: 'e1',
        url: 'https://shop.example.com/keyboard',
        bodyLocation: BodyLocation.file,
        fileOffset: offset,
        fileLength: length,
      );

      await controller.start(
        query: 'keyboard',
        allEntries: [e1],
        filePath: tempFilePath,
      );

      expect(controller.results!.length, equals(1));
    });

    test('Gracefully ignores invalid file paths and corrupted offsets',
        () async {
      final e1 = _buildEntry(
        id: 'e1',
        bodyLocation: BodyLocation.file,
        fileOffset: 999999,
        fileLength: 5000,
      );

      await controller.start(
        query: 'non_existent_data',
        allEntries: [e1],
        filePath: '${tempDir.path}/missing_file.tmp',
      );

      expect(controller.results, isNotNull);
      expect(controller.results, isEmpty);
    });
  });

  group('MasterSearchController: Boundary Cases & Race Resistance', () {
    test('Treats special regex characters as plain literal substrings',
        () async {
      final e1 = _buildEntry(
          id: 'e1', url: 'https://api.example.com/test?filter=.*&tag=[a-z]');
      final e2 = _buildEntry(
          id: 'e2', url: 'https://api.example.com/test?filter=normal');

      await controller.start(
        query: '.*&tag=[a-z]',
        allEntries: [e1, e2],
        filePath: null,
      );

      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('e1'));
    });

    test('Supports unicode, accents, emojis, and symbols in search query',
        () async {
      final e1 = _buildEntry(
          id: 'e1', url: 'https://api.example.com/users/nguy%E1%BB%85n');
      final body = Uint8List.fromList(
          utf8.encode('{"greeting": "Xin chào thế giới 🚀"}'));
      final e2 = _buildEntry(
        id: 'e2',
        bodyLocation: BodyLocation.memory,
        inlineResponseBody: body,
      );

      await controller.start(
        query: 'Xin chào',
        allEntries: [e1, e2],
        filePath: null,
      );
      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('e2'));

      await controller.start(
        query: '🚀',
        allEntries: [e1, e2],
        filePath: null,
      );
      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('e2'));
    });

    test('Rapid consecutive search calls cancel prior generations cleanly',
        () async {
      final e1 = _buildEntry(id: 'e1', url: 'https://api.example.com/first');
      final e2 = _buildEntry(id: 'e2', url: 'https://api.example.com/second');

      final future1 = controller.start(
        query: 'first',
        allEntries: [e1, e2],
        filePath: null,
      );
      final future2 = controller.start(
        query: 'second',
        allEntries: [e1, e2],
        filePath: null,
      );

      await Future.wait([future1, future2]);

      expect(controller.query, equals('second'));
      expect(controller.results!.length, equals(1));
      expect(controller.results!.first.id, equals('e2'));
    });

    test('Search on empty index returns empty results without error', () async {
      await controller.start(
        query: 'anything',
        allEntries: [],
        filePath: null,
      );

      expect(controller.results, isNotNull);
      expect(controller.results, isEmpty);
    });
  });

  group('MasterSearchController: Notification Throttling & Handle Reuse', () {
    test(
        'Throttles UI notifications during active search and forces final notification',
        () async {
      var notificationCount = 0;
      controller.addListener(() => notificationCount++);

      final entries = <IndexEntry>[];
      for (var i = 0; i < 30; i++) {
        final bodyBytes =
            Uint8List.fromList(utf8.encode('{"item": "target_$i"}'));
        entries.add(
          _buildEntry(
            id: 'mem_$i',
            url: 'https://api.example.com/item/$i',
            bodyLocation: BodyLocation.memory,
            inlineResponseBody: bodyBytes,
          ),
        );
      }

      await controller.start(
        query: 'target_',
        allEntries: entries,
        filePath: null,
      );

      expect(controller.results, isNotNull);
      expect(controller.results!.length, equals(30));
      expect(notificationCount, lessThan(30));
      expect(notificationCount, greaterThan(0));
    });

    test('Phase 3 scans multiple batches with single handle reuse', () async {
      final entries = <IndexEntry>[];
      for (var i = 0; i < 10; i++) {
        final packed = _createPackedBody(
          requestBody: '{"batch": "test_$i"}',
          responseBody: '{"payload": "token_match_$i"}',
        );
        final (offset, length) = await bodyStore.append(packed);
        entries.add(
          _buildEntry(
            id: 'file_$i',
            url: 'https://api.example.com/record/$i',
            bodyLocation: BodyLocation.file,
            fileOffset: offset,
            fileLength: length,
          ),
        );
      }

      await controller.start(
        query: 'token_match_',
        allEntries: entries,
        filePath: tempFilePath,
      );

      expect(controller.results, isNotNull);
      expect(controller.results!.length, equals(10));
    });

    test('dispose cancels active throttle timer cleanly without exception',
        () async {
      final controllerToDispose = MasterSearchController();
      final bodyBytes =
          Uint8List.fromList(utf8.encode('{"data": "disposable_test"}'));
      final entry = _buildEntry(
        id: 'disp_1',
        url: 'https://api.example.com/disp',
        bodyLocation: BodyLocation.memory,
        inlineResponseBody: bodyBytes,
      );

      final searchFuture = controllerToDispose.start(
        query: 'disposable_test',
        allEntries: [entry],
        filePath: null,
      );

      controllerToDispose.dispose();
      await searchFuture;
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(true, isTrue);
    });

    test('getScopes accurately identifies URL, Headers, Body, and Error scopes',
        () async {
      final entryUrl = _buildEntry(
        id: 'scope_url',
        url: 'https://api.example.com/special_endpoint',
      );
      final entryHeader = _buildEntry(
        id: 'scope_header',
        url: 'https://api.example.com/other',
        requestHeaders: {'X-Custom-Token': 'special_secret'},
      );
      final entryError = _buildEntry(
        id: 'scope_error',
        url: 'https://api.example.com/failed',
        hasError: true,
        errorMessage: 'special_failure connection timeout',
      );
      final entryBody = _buildEntry(
        id: 'scope_body',
        url: 'https://api.example.com/data',
        bodyLocation: BodyLocation.memory,
        inlineResponseBody:
            Uint8List.fromList(utf8.encode('{"result": "special_payload"}')),
      );

      final searchCtrl = MasterSearchController();
      await searchCtrl.start(
        query: 'special_',
        allEntries: [entryUrl, entryHeader, entryError, entryBody],
        filePath: null,
      );

      expect(
          searchCtrl.results!.map((e) => e.id),
          containsAll(
              ['scope_url', 'scope_header', 'scope_error', 'scope_body']));
      expect(searchCtrl.getScopes('scope_url'), equals({SearchMatchScope.url}));
      expect(searchCtrl.getScopes('scope_header'),
          equals({SearchMatchScope.headers}));
      expect(searchCtrl.getScopes('scope_error'),
          equals({SearchMatchScope.error}));
      expect(
          searchCtrl.getScopes('scope_body'), equals({SearchMatchScope.body}));

      searchCtrl.cancel();
      expect(searchCtrl.getScopes('scope_url'), isEmpty);
    });
  });
}
