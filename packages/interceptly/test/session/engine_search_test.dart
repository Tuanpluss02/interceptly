// ignore_for_file: invalid_use_of_internal_member
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/engine/body_store.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/search_match_scope.dart';
import 'package:interceptly/src/model/search_result.dart';

Uint8List _createPackedBody({
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

IndexEntry _buildEntry({
  required String id,
  String method = 'GET',
  String url = 'https://api.example.com/items',
  int statusCode = 200,
  int durationMs = 25,
  int requestSizeBytes = 128,
  int responseSizeBytes = 256,
  bool hasError = false,
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
    timestamp: DateTime.now(),
    hasError: hasError,
    requestTruncation: const BodyTruncation.complete(0),
    responseTruncation: const BodyTruncation.complete(0),
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
  late InterceptlyEngine engine;

  setUp(() async {
    await InterceptlyEngine.resetForTesting();
    engine = InterceptlyEngine.instance;
  });

  tearDown(() async {
    await InterceptlyEngine.resetForTesting();
  });

  group('InterceptlyEngine.search', () {
    test('matches structured fields: URL, method, headers, error', () async {
      engine.recordEntryForTesting(_buildEntry(
        id: '1',
        method: 'POST',
        url: 'https://api.example.com/checkout',
      ));
      engine.recordEntryForTesting(_buildEntry(
        id: '2',
        requestHeaders: {'X-Api-Key': 'my-secret-key-123'},
      ));
      engine.recordEntryForTesting(_buildEntry(
        id: '3',
        hasError: true,
        errorMessage: 'Connection timeout',
      ));

      final resCheckout = await engine.search(query: 'checkout');
      expect(resCheckout.length, 1);
      expect(resCheckout.first.summary.id, '1');
      expect(resCheckout.first.matchScopes, contains(SearchMatchScope.url));

      final resKey = await engine.search(query: 'my-secret-key-123');
      expect(resKey.length, 1);
      expect(resKey.first.summary.id, '2');
      expect(resKey.first.matchScopes, contains(SearchMatchScope.headers));

      final resError = await engine.search(query: 'timeout');
      expect(resError.length, 1);
      expect(resError.first.summary.id, '3');
      expect(resError.first.matchScopes, contains(SearchMatchScope.error));
    });

    test('matches in-memory request/response body', () async {
      final reqBytes = Uint8List.fromList(utf8.encode('{"customer":"alice"}'));
      engine.recordEntryForTesting(_buildEntry(
        id: '10',
        inlineRequestBody: reqBytes,
      ));

      final res = await engine.search(query: 'alice');
      expect(res.length, 1);
      expect(res.first.summary.id, '10');
      expect(res.first.matchScopes, contains(SearchMatchScope.body));
    });

    test('skips body when searchBody is false', () async {
      final reqBytes = Uint8List.fromList(utf8.encode('{"customer":"bob"}'));
      engine.recordEntryForTesting(_buildEntry(
        id: '20',
        inlineRequestBody: reqBytes,
      ));

      final resFalse = await engine.search(query: 'bob', searchBody: false);
      expect(resFalse, isEmpty);

      final resTrue = await engine.search(query: 'bob', searchBody: true);
      expect(resTrue.length, 1);
    });

    test('applies statusFilter, sinceId cursor, and limit', () async {
      for (var i = 1; i <= 10; i++) {
        engine.recordEntryForTesting(_buildEntry(
          id: '$i',
          statusCode: i % 2 == 0 ? 500 : 200,
          url: 'https://api.example.com/resource_$i',
        ));
      }

      // Filter by status 5xx
      final resFailed = await engine.search(
        query: 'resource',
        statusFilter: '5xx',
      );
      expect(resFailed.every((r) => r.summary.statusCode == 500), isTrue);

      // Limit clamp
      final resLimited = await engine.search(
        query: 'resource',
        limit: 3,
      );
      expect(resLimited.length, 3);

      // Cursor sinceId (entries are newest-first: 10, 9, 8...)
      final resSince = await engine.search(
        query: 'resource',
        sinceId: '8',
      );
      // '10' and '9' are newer than '8'
      expect(resSince.map((r) => r.summary.id).toList(), ['10', '9']);
    });
  });
}
