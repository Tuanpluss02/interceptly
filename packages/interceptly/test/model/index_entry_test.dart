import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/request_filter.dart';
import 'package:interceptly/src/model/request_summary.dart';

void main() {
  IndexEntry createEntry({
    String id = 'req-1',
    String method = 'GET',
    String url = 'https://api.example.com/v1/users',
    int statusCode = 200,
    int durationMs = 120,
    int requestSizeBytes = 64,
    int responseSizeBytes = 256,
    DateTime? timestamp,
    bool hasError = false,
    BodyTruncation requestTruncation = const BodyTruncation.complete(64),
    BodyTruncation responseTruncation = const BodyTruncation.complete(256),
    Map<String, String> requestHeaders = const {'accept': 'application/json'},
    Map<String, String> responseHeaders = const {'content-type': 'application/json'},
    String? requestContentType = 'application/json',
    String? responseContentType = 'application/json',
    String? errorType,
    String? errorMessage,
    BodyLocation bodyLocation = BodyLocation.memory,
    Uint8List? inlineRequestBody,
    Uint8List? inlineResponseBody,
    int? fileOffset,
    int? fileLength,
    String? domain,
  }) {
    return IndexEntry(
      id: id,
      method: method,
      url: url,
      statusCode: statusCode,
      durationMs: durationMs,
      requestSizeBytes: requestSizeBytes,
      responseSizeBytes: responseSizeBytes,
      timestamp: timestamp ?? DateTime(2026, 10, 14, 12, 0, 0),
      hasError: hasError,
      requestTruncation: requestTruncation,
      responseTruncation: responseTruncation,
      requestHeaders: requestHeaders,
      responseHeaders: responseHeaders,
      requestContentType: requestContentType,
      responseContentType: responseContentType,
      errorType: errorType,
      errorMessage: errorMessage,
      bodyLocation: bodyLocation,
      inlineRequestBody: inlineRequestBody,
      inlineResponseBody: inlineResponseBody,
      fileOffset: fileOffset,
      fileLength: fileLength,
      domain: domain,
    );
  }

  group('IndexEntry domain pre-parsing', () {
    test('extracts hostname from URL upon creation', () {
      final entry = createEntry(url: 'https://service.domain.com/v2/items?page=1');
      expect(entry.domain, equals('service.domain.com'));
    });

    test('extracts hostname with custom port', () {
      final entry = createEntry(url: 'http://localhost:8080/health');
      expect(entry.domain, equals('localhost'));
    });

    test('falls back to unknown for malformed or schemeless invalid URLs', () {
      final entry = createEntry(url: 'invalid-url');
      expect(entry.domain, equals('unknown'));
    });

    test('allows explicit domain override in constructor', () {
      final entry = createEntry(
        url: 'https://api.example.com/data',
        domain: 'custom.override.com',
      );
      expect(entry.domain, equals('custom.override.com'));
    });
  });

  group('IndexEntry.copyWith', () {
    test('returns equal copy when no arguments are provided', () {
      final original = createEntry(
        inlineRequestBody: Uint8List.fromList([1, 2, 3]),
        inlineResponseBody: Uint8List.fromList([4, 5, 6]),
        fileOffset: 100,
        fileLength: 200,
      );
      final copy = original.copyWith();

      expect(copy.id, equals(original.id));
      expect(copy.method, equals(original.method));
      expect(copy.url, equals(original.url));
      expect(copy.domain, equals(original.domain));
      expect(copy.statusCode, equals(original.statusCode));
      expect(copy.durationMs, equals(original.durationMs));
      expect(copy.requestSizeBytes, equals(original.requestSizeBytes));
      expect(copy.responseSizeBytes, equals(original.responseSizeBytes));
      expect(copy.timestamp, equals(original.timestamp));
      expect(copy.hasError, equals(original.hasError));
      expect(copy.requestTruncation, equals(original.requestTruncation));
      expect(copy.responseTruncation, equals(original.responseTruncation));
      expect(copy.requestHeaders, equals(original.requestHeaders));
      expect(copy.responseHeaders, equals(original.responseHeaders));
      expect(copy.requestContentType, equals(original.requestContentType));
      expect(copy.responseContentType, equals(original.responseContentType));
      expect(copy.errorType, equals(original.errorType));
      expect(copy.errorMessage, equals(original.errorMessage));
      expect(copy.bodyLocation, equals(original.bodyLocation));
      expect(copy.inlineRequestBody, equals(original.inlineRequestBody));
      expect(copy.inlineResponseBody, equals(original.inlineResponseBody));
      expect(copy.fileOffset, equals(original.fileOffset));
      expect(copy.fileLength, equals(original.fileLength));
    });

    test('updates specified scalar fields while retaining all others', () {
      final original = createEntry();
      final copy = original.copyWith(
        statusCode: 404,
        durationMs: 450,
        hasError: true,
        errorType: 'HttpException',
        errorMessage: 'Not Found',
      );

      expect(copy.statusCode, equals(404));
      expect(copy.durationMs, equals(450));
      expect(copy.hasError, isTrue);
      expect(copy.errorType, equals('HttpException'));
      expect(copy.errorMessage, equals('Not Found'));
      // Unchanged fields:
      expect(copy.id, equals(original.id));
      expect(copy.url, equals(original.url));
      expect(copy.domain, equals(original.domain));
      expect(copy.method, equals(original.method));
      expect(copy.requestHeaders, equals(original.requestHeaders));
    });

    test('re-parses domain when url changes without explicit domain', () {
      final original = createEntry(url: 'https://api.initial.com/v1');
      expect(original.domain, equals('api.initial.com'));

      final copy = original.copyWith(url: 'https://newdomain.org/v2');
      expect(copy.url, equals('https://newdomain.org/v2'));
      expect(copy.domain, equals('newdomain.org'));
    });

    test('respects explicit domain when url changes and domain is provided', () {
      final original = createEntry(url: 'https://api.initial.com/v1');
      final copy = original.copyWith(
        url: 'https://newdomain.org/v2',
        domain: 'custom-explicit.org',
      );
      expect(copy.url, equals('https://newdomain.org/v2'));
      expect(copy.domain, equals('custom-explicit.org'));
    });
  });

  group('RequestFilter.matches with pre-parsed domain', () {
    test('matches IndexEntry by pre-parsed domain', () {
      final filter = RequestFilter(domains: {'api.fast.com'});
      final entry = createEntry(url: 'https://api.fast.com/resource');
      expect(filter.matches(entry), isTrue);

      final otherEntry = createEntry(url: 'https://api.slow.com/resource');
      expect(filter.matches(otherEntry), isFalse);
    });

    test('matches plain RequestSummary fallback to extractDomain', () {
      final filter = RequestFilter(domains: {'example.org'});
      final summary = RequestSummary(
        id: 's-1',
        method: 'GET',
        url: 'https://example.org/path',
        statusCode: 200,
        durationMs: 10,
        requestSizeBytes: 0,
        responseSizeBytes: 0,
        timestamp: DateTime(2026),
        hasError: false,
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation.complete(0),
      );

      expect(filter.matches(summary), isTrue);
    });
  });
}
