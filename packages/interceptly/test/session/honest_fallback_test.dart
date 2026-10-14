import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/raw_capture.dart';
import 'package:interceptly/src/session/writer_isolate.dart';

RawCapture _createCapture({
  String id = '1',
  String method = 'POST',
  String url = 'https://api.com',
  Map<String, String> requestHeaders = const {},
  Map<String, String> responseHeaders = const {},
  int statusCode = 200,
  int durationMs = 10,
  DateTime? timestamp,
  TransferableTypedData? requestBodyBytes,
  TransferableTypedData? responseBodyBytes,
  int? requestSizeBytes,
  int? responseSizeBytes,
  String? requestContentType,
  String? responseContentType,
}) {
  return RawCapture(
    id: id,
    method: method,
    url: url,
    requestHeaders: requestHeaders,
    responseHeaders: responseHeaders,
    statusCode: statusCode,
    durationMs: durationMs,
    timestamp: timestamp ?? DateTime(2026, 10, 14),
    requestBodyBytes: requestBodyBytes,
    responseBodyBytes: responseBodyBytes,
    requestSizeBytes: requestSizeBytes,
    responseSizeBytes: responseSizeBytes,
    requestContentType: requestContentType,
    responseContentType: responseContentType,
  );
}

void main() {
  group('Honest Fallback', () {
    test(
        'fallback entry preserves original size and reports storage truncation with hasDataLoss=true',
        () {
      final capture = _createCapture(
        id: '1',
        method: 'POST',
        url: 'https://api.com',
        requestSizeBytes: 500,
      );
      final entry = fallbackEntryForTesting(capture);
      expect(entry.requestSizeBytes, equals(500));
      expect(entry.requestTruncation.hasDataLoss, isTrue);
      expect(entry.requestTruncation.stage, equals(TruncationStage.storage));
      expect(entry.requestTruncation.retainedBytes, equals(0));
      expect(entry.requestTruncation.originalBytes, equals(500));

      expect(entry.responseSizeBytes, equals(0));
      expect(entry.responseTruncation.hasDataLoss, isFalse);
    });

    test('fallback entry preserves response size and marks response truncated', () {
      final capture = _createCapture(
        id: '2',
        method: 'GET',
        url: 'https://api.com/items',
        responseSizeBytes: 1200,
      );
      final entry = fallbackEntryForTesting(capture);
      expect(entry.requestSizeBytes, equals(0));
      expect(entry.requestTruncation.hasDataLoss, isFalse);

      expect(entry.responseSizeBytes, equals(1200));
      expect(entry.responseTruncation.hasDataLoss, isTrue);
      expect(entry.responseTruncation.stage, equals(TruncationStage.storage));
      expect(entry.responseTruncation.retainedBytes, equals(0));
      expect(entry.responseTruncation.originalBytes, equals(1200));
    });

    test('fallback entry preserves both request and response sizes when present', () {
      final capture = _createCapture(
        id: '3',
        method: 'PUT',
        url: 'https://api.com/items/1',
        requestSizeBytes: 300,
        responseSizeBytes: 800,
      );
      final entry = fallbackEntryForTesting(capture);
      expect(entry.requestSizeBytes, equals(300));
      expect(entry.requestTruncation.hasDataLoss, isTrue);
      expect(entry.requestTruncation.stage, equals(TruncationStage.storage));

      expect(entry.responseSizeBytes, equals(800));
      expect(entry.responseTruncation.hasDataLoss, isTrue);
      expect(entry.responseTruncation.stage, equals(TruncationStage.storage));
    });

    test('fallback entry with no bodies reports zero size and no data loss', () {
      final capture = _createCapture(
        id: '4',
        method: 'HEAD',
        url: 'https://api.com/status',
      );
      final entry = fallbackEntryForTesting(capture);
      expect(entry.requestSizeBytes, equals(0));
      expect(entry.requestTruncation.hasDataLoss, isFalse);
      expect(entry.responseSizeBytes, equals(0));
      expect(entry.responseTruncation.hasDataLoss, isFalse);
    });

    test('fallback entry determines size from requestBodyBytes if requestSizeBytes null', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final capture = _createCapture(
        id: '5',
        method: 'POST',
        url: 'https://api.com',
        requestBodyBytes: RawCapture.wrapBytes(bytes),
      );
      final entry = fallbackEntryForTesting(capture);
      expect(entry.requestSizeBytes, equals(5));
      expect(entry.requestTruncation.hasDataLoss, isTrue);
      expect(entry.requestTruncation.stage, equals(TruncationStage.storage));
    });
  });
}
