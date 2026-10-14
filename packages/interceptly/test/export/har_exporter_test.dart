import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/export/har_exporter.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/request_record.dart';

void main() {
  group('HarExporter', () {
    test('uses creator version 2.0.0', () {
      final har = HarExporter.fromRecords([_record()]);
      final log = har['log'] as Map<String, Object?>;
      final creator = log['creator'] as Map<String, Object?>;

      expect(creator['name'], 'Interceptly');
      expect(creator['version'], '2.0.0');
    });

    test('exports binary response body as base64 with encoding: base64 when contentType is binary', () {
      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final record = _record(
        responseContentType: 'image/png',
        responseSizeBytes: pngBytes.length,
        responseBodyBytes: pngBytes,
      );

      final har = HarExporter.fromRecords([record]);
      final entries = (har['log'] as Map<String, Object?>)['entries'] as List;
      final res = (entries.first as Map<String, Object?>)['response'] as Map<String, Object?>;
      final content = res['content'] as Map<String, Object?>;

      expect(content['mimeType'], 'image/png');
      expect(content['size'], pngBytes.length);
      expect(content['encoding'], 'base64');
      expect(content['text'], base64Encode(pngBytes));
    });

    test('exports binary response body as base64 with encoding: base64 when bytes fail UTF-8 decoding', () {
      final nonUtf8Bytes = Uint8List.fromList([0xFF, 0xFE, 0xFD, 0xFC]);
      final record = _record(
        responseContentType: 'application/octet-stream',
        responseSizeBytes: nonUtf8Bytes.length,
        responseBodyBytes: nonUtf8Bytes,
      );

      final har = HarExporter.fromRecords([record]);
      final entries = (har['log'] as Map<String, Object?>)['entries'] as List;
      final res = (entries.first as Map<String, Object?>)['response'] as Map<String, Object?>;
      final content = res['content'] as Map<String, Object?>;

      expect(content['encoding'], 'base64');
      expect(content['text'], base64Encode(nonUtf8Bytes));
    });

    test('exports text response body as plain decoded string without encoding field', () {
      const jsonText = '{"status":"ok","count":42}';
      final textBytes = Uint8List.fromList(utf8.encode(jsonText));
      final record = _record(
        responseContentType: 'application/json',
        responseSizeBytes: textBytes.length,
        responseBodyBytes: textBytes,
      );

      final har = HarExporter.fromRecords([record]);
      final entries = (har['log'] as Map<String, Object?>)['entries'] as List;
      final res = (entries.first as Map<String, Object?>)['response'] as Map<String, Object?>;
      final content = res['content'] as Map<String, Object?>;

      expect(content['mimeType'], 'application/json');
      expect(content['text'], jsonText);
      expect(content.containsKey('encoding'), isFalse);
    });

    test('falls back to preview when responseBodyBytes is null', () {
      final record = _record(
        responseContentType: 'application/json',
        responseSizeBytes: 15,
        responseBodyPreview: '{"preview":true}',
      );

      final har = HarExporter.fromRecords([record]);
      final entries = (har['log'] as Map<String, Object?>)['entries'] as List;
      final res = (entries.first as Map<String, Object?>)['response'] as Map<String, Object?>;
      final content = res['content'] as Map<String, Object?>;

      expect(content['text'], '{"preview":true}');
      expect(content.containsKey('encoding'), isFalse);
    });

    test('outputs empty string when responseBodyBytes is null and preview is placeholder', () {
      final record = _record(
        responseContentType: 'image/png',
        responseSizeBytes: 1024,
        responseBodyPreview: '\x00[binary: 1024 bytes]',
      );

      final har = HarExporter.fromRecords([record]);
      final entries = (har['log'] as Map<String, Object?>)['entries'] as List;
      final res = (entries.first as Map<String, Object?>)['response'] as Map<String, Object?>;
      final content = res['content'] as Map<String, Object?>;

      expect(content['text'], '');
      expect(content.containsKey('encoding'), isFalse);
    });

    test('includes comment in response content when responseTruncation hasDataLoss is true (storage)', () {
      final record = _record(
        responseContentType: 'application/json',
        responseSizeBytes: 5000,
        responseBodyPreview: '{"truncated":true}',
        responseTruncation: const BodyTruncation(
          originalBytes: 5000,
          retainedBytes: 1024,
          stage: TruncationStage.storage,
        ),
      );

      final har = HarExporter.fromRecords([record]);
      final entries = (har['log'] as Map<String, Object?>)['entries'] as List;
      final res = (entries.first as Map<String, Object?>)['response'] as Map<String, Object?>;
      final content = res['content'] as Map<String, Object?>;

      expect(
        content['comment'],
        'Payload truncated from original 5000 bytes',
      );
    });

    test('includes comment in response content when responseTruncation hasDataLoss is true (storageAndPreview)', () {
      final record = _record(
        responseContentType: 'application/json',
        responseSizeBytes: 5000,
        responseBodyPreview: '{"truncated":true}',
        responseTruncation: const BodyTruncation(
          originalBytes: 5000,
          retainedBytes: 512,
          stage: TruncationStage.storageAndPreview,
        ),
      );

      final har = HarExporter.fromRecords([record]);
      final entries = (har['log'] as Map<String, Object?>)['entries'] as List;
      final res = (entries.first as Map<String, Object?>)['response'] as Map<String, Object?>;
      final content = res['content'] as Map<String, Object?>;

      expect(
        content['comment'],
        'Payload truncated from original 5000 bytes',
      );
    });

    test('omits comment in response content when complete (hasDataLoss is false)', () {
      final record = _record(
        responseContentType: 'application/json',
        responseSizeBytes: 100,
        responseBodyPreview: '{"truncated":false}',
        responseTruncation: const BodyTruncation.complete(100),
      );

      final har = HarExporter.fromRecords([record]);
      final entries = (har['log'] as Map<String, Object?>)['entries'] as List;
      final res = (entries.first as Map<String, Object?>)['response'] as Map<String, Object?>;
      final content = res['content'] as Map<String, Object?>;

      expect(content.containsKey('comment'), isFalse);
    });

    test('omits comment in response content when preview only (hasDataLoss is false)', () {
      final record = _record(
        responseContentType: 'application/json',
        responseSizeBytes: 5000,
        responseBodyPreview: '{"truncated":false}',
        responseTruncation: const BodyTruncation(
          originalBytes: 5000,
          retainedBytes: 500,
          stage: TruncationStage.preview,
        ),
      );

      final har = HarExporter.fromRecords([record]);
      final entries = (har['log'] as Map<String, Object?>)['entries'] as List;
      final res = (entries.first as Map<String, Object?>)['response'] as Map<String, Object?>;
      final content = res['content'] as Map<String, Object?>;

      expect(content.containsKey('comment'), isFalse);
    });
  });
}

RequestRecord _record({
  String method = 'GET',
  String url = 'https://api.example.com/test',
  int statusCode = 200,
  int durationMs = 50,
  int requestSizeBytes = 0,
  int responseSizeBytes = 0,
  BodyTruncation responseTruncation = const BodyTruncation.complete(0),
  String? requestContentType,
  String? responseContentType,
  Map<String, String>? requestHeaders,
  Map<String, String>? responseHeaders,
  Uint8List? requestBodyBytes,
  Uint8List? responseBodyBytes,
  String? requestBodyPreview,
  String? responseBodyPreview,
}) {
  return RequestRecord(
    id: 'test-id',
    method: method,
    url: url,
    statusCode: statusCode,
    durationMs: durationMs,
    requestSizeBytes: requestSizeBytes,
    responseSizeBytes: responseSizeBytes,
    timestamp: DateTime.utc(2026, 1, 1),
    requestContentType: requestContentType,
    responseContentType: responseContentType,
    requestHeaders: requestHeaders ?? {},
    responseHeaders: responseHeaders ?? {},
    requestBodyBytes: requestBodyBytes,
    responseBodyBytes: responseBodyBytes,
    requestBodyPreview: requestBodyPreview,
    responseBodyPreview: responseBodyPreview,
    responseTruncation: responseTruncation,
  );
}
