// ignore_for_file: invalid_use_of_internal_member
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/engine/body_store.dart';
import 'package:interceptly/src/engine/search_matcher.dart';
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
  String url = 'https://api.example.com/items?token=secret123',
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
  );
}

void main() {
  group('SearchMatcher.matchStructured', () {
    test('matches url path, method, and query parameters', () {
      final entry = _buildEntry(
        id: '1',
        method: 'POST',
        url: 'https://api.example.com/checkout?currency=usd',
      );

      expect(
        SearchMatcher.matchStructured(entry, 'checkout'),
        contains(SearchMatchScope.url),
      );
      expect(
        SearchMatcher.matchStructured(entry, 'post'),
        contains(SearchMatchScope.url),
      );
      expect(
        SearchMatcher.matchStructured(entry, 'currency=usd'),
        contains(SearchMatchScope.url),
      );
      expect(SearchMatcher.matchStructured(entry, 'nonexistent'), isEmpty);
    });

    test('matches request and response header keys and values', () {
      final entry = _buildEntry(
        id: '2',
        requestHeaders: {'Authorization': 'Bearer secret-token-xyz'},
        responseHeaders: {'x-custom-header': 'custom-value-123'},
      );

      expect(
        SearchMatcher.matchStructured(entry, 'authorization'),
        contains(SearchMatchScope.headers),
      );
      expect(
        SearchMatcher.matchStructured(entry, 'secret-token-xyz'),
        contains(SearchMatchScope.headers),
      );
      expect(
        SearchMatcher.matchStructured(entry, 'x-custom-header'),
        contains(SearchMatchScope.headers),
      );
      expect(
        SearchMatcher.matchStructured(entry, 'custom-value-123'),
        contains(SearchMatchScope.headers),
      );
    });

    test('matches error message and error type', () {
      final entry = _buildEntry(
        id: '3',
        hasError: true,
        errorMessage: 'SocketException: Connection refused',
        errorType: 'NetworkException',
      );

      expect(
        SearchMatcher.matchStructured(entry, 'connection refused'),
        contains(SearchMatchScope.error),
      );
      expect(
        SearchMatcher.matchStructured(entry, 'networkexception'),
        contains(SearchMatchScope.error),
      );
    });
  });

  group('SearchMatcher.matchInlineBody', () {
    test('matches text inside inline request and response bodies', () {
      final reqBytes = Uint8List.fromList(utf8.encode('{"user_id": 42}'));
      final resBytes = Uint8List.fromList(utf8.encode('{"order_id": 9999}'));
      final entry = _buildEntry(
        id: '4',
        inlineRequestBody: reqBytes,
        inlineResponseBody: resBytes,
      );

      expect(SearchMatcher.matchInlineBody(entry, 'user_id'), isTrue);
      expect(SearchMatcher.matchInlineBody(entry, 'order_id'), isTrue);
      expect(SearchMatcher.matchInlineBody(entry, '9999'), isTrue);
      expect(SearchMatcher.matchInlineBody(entry, 'missing_field'), isFalse);
    });

    test('returns false when inline bodies are null', () {
      final entry = _buildEntry(id: '5');
      expect(SearchMatcher.matchInlineBody(entry, 'anything'), isFalse);
    });
  });

  group('SearchMatcher.matchFileBody', () {
    late Directory tempDir;
    late String filePath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('search_matcher_test_');
      filePath = '${tempDir.path}/bodies.bin';
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('reads and matches text inside file-backed body', () async {
      final packed = _createPackedBody(
        requestBody: '{"action":"login"}',
        responseBody: '{"token":"jwt-access-abc"}',
      );

      final file = File(filePath);
      await file.writeAsBytes(packed);
      final offset = 0;
      final length = packed.length;
      final raf = await BodyStore.openReadHandle(filePath);

      try {
        final matchesAction = await SearchMatcher.matchFileBody(
          raf,
          offset,
          length,
          'action',
        );
        final matchesToken = await SearchMatcher.matchFileBody(
          raf,
          offset,
          length,
          'jwt-access-abc',
        );
        final matchesMissing = await SearchMatcher.matchFileBody(
          raf,
          offset,
          length,
          'nonexistent',
        );

        expect(matchesAction, isTrue);
        expect(matchesToken, isTrue);
        expect(matchesMissing, isFalse);
      } finally {
        await raf.close();
      }
    });
  });
}
