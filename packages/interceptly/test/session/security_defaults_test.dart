import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/model/index_entry.dart';

const MethodChannel _channel =
    MethodChannel('plugins.flutter.io/path_provider');

const Set<String> _optInHeaders = {
  'authorization',
  'cookie',
  'set-cookie',
  'x-api-key',
};

Uint8List _bytes(String text) => Uint8List.fromList(text.codeUnits);

String _text(Uint8List? bytes) =>
    bytes == null ? '<null>' : String.fromCharCodes(bytes);

Future<IndexEntry> _waitForEntry(InspectorSession session, String id) async {
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(end)) {
    for (final entry in session.entries) {
      if (entry.id == id && entry is IndexEntry) return entry;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('entry $id never arrived');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('security_defaults_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tempDir.path;
      return null;
    });
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Security defaults stay empty and opt-in', () {
    test('redactedHeaders defaults to empty', () {
      const settings = InterceptlySettings();
      expect(settings.redactedHeaders, isEmpty);
    });

    test('redactedQueryParams defaults to empty', () {
      const settings = InterceptlySettings();
      expect(settings.redactedQueryParams, isEmpty);
    });

    test('bodyRedactor defaults to null', () {
      const settings = InterceptlySettings();
      expect(settings.bodyRedactor, isNull);
    });

    test('normalized query params default to empty', () {
      const settings = InterceptlySettings();
      expect(settings.normalizedRedactedQueryParams, isEmpty);
    });
  });

  group('Opt-in header redaction', () {
    test('four opt-in headers mask case-insensitively', () {
      const settings = InterceptlySettings(redactedHeaders: _optInHeaders);
      final redacted = CaptureGuard.redactHeaders(
        {
          'Authorization': 'Bearer secret',
          'COOKIE': 'session=abc',
          'Set-Cookie': 'id=1',
          'X-API-KEY': 'key-123',
          'Content-Type': 'application/json',
        },
        settings.normalizedRedactedHeaders,
      );
      expect(redacted['Authorization'], '[REDACTED]');
      expect(redacted['COOKIE'], '[REDACTED]');
      expect(redacted['Set-Cookie'], '[REDACTED]');
      expect(redacted['X-API-KEY'], '[REDACTED]');
      expect(redacted['Content-Type'], 'application/json');
    });

    test('default empty set leaves headers untouched', () {
      const settings = InterceptlySettings();
      final original = {'Authorization': 'Bearer secret'};
      final result = CaptureGuard.redactHeaders(
        original,
        settings.normalizedRedactedHeaders,
      );
      expect(identical(original, result), isTrue);
    });
  });

  group('sanitizeUrl', () {
    test('empty set is a passthrough', () {
      const url =
          'https://api.example.com/items?token=abc&api_key=def&password=ghi&page=2';
      expect(CaptureGuard.sanitizeUrl(url), url);
      expect(CaptureGuard.sanitizeUrl(url, const {}), url);
    });

    test('custom keys mask only matching params', () {
      const settings = InterceptlySettings(
        redactedQueryParams: {'token', 'api_key', 'password'},
      );
      final clean = CaptureGuard.sanitizeUrl(
        'https://api.example.com/items?page=2&sort=asc',
        settings.normalizedRedactedQueryParams,
      );
      expect(clean, 'https://api.example.com/items?page=2&sort=asc');
      final masked = CaptureGuard.sanitizeUrl(
        'https://api.example.com/items?token=abc&page=2&password=ghi',
        settings.normalizedRedactedQueryParams,
      );
      final uri = Uri.parse(masked);
      expect(uri.queryParameters['token'], '[REDACTED]');
      expect(uri.queryParameters['password'], '[REDACTED]');
      expect(uri.queryParameters['page'], '2');
      expect(masked.contains('abc'), isFalse);
      expect(masked.contains('ghi'), isFalse);
    });

    test('matching is case-insensitive', () {
      const settings = InterceptlySettings(
        redactedQueryParams: {'token'},
      );
      final masked = CaptureGuard.sanitizeUrl(
        'https://api.example.com/items?TOKEN=abc',
        settings.normalizedRedactedQueryParams,
      );
      expect(Uri.parse(masked).queryParameters['TOKEN'], '[REDACTED]');
    });
  });

  group('bodyRedactor', () {
    test('null bodyRedactor keeps recordPending byte-identical', () {
      final session = InspectorSession();
      addTearDown(session.dispose);
      session.recordPending(
        id: 'plain-body',
        method: 'POST',
        url: 'https://api.example.com/submit?token=abc',
        timestamp: DateTime(2026),
        requestHeaders: const {'Authorization': 'Bearer secret'},
        requestBodyBytes: _bytes('{"user":"ada"}'),
      );
      final entry = session.entries.singleWhere((e) => e.id == 'plain-body')
          as IndexEntry;
      expect(entry.url, 'https://api.example.com/submit?token=abc');
      expect(entry.requestHeaders['Authorization'], 'Bearer secret');
      expect(_text(entry.inlineRequestBody), '{"user":"ada"}');
    });

    test('custom bodyRedactor runs before persist in recordPending', () {
      var calls = 0;
      final session = InspectorSession(
        settings: InterceptlySettings(
          bodyRedactor: (body) {
            calls++;
            return _bytes('scrubbed');
          },
        ),
      );
      addTearDown(session.dispose);
      session.recordPending(
        id: 'redacted-body',
        method: 'POST',
        url: 'https://api.example.com/submit',
        timestamp: DateTime(2026),
        requestBodyBytes: _bytes('{"secret":"value"}'),
      );
      expect(calls, 1);
      final entry = session.entries.singleWhere((e) => e.id == 'redacted-body')
          as IndexEntry;
      expect(_text(entry.inlineRequestBody), 'scrubbed');
    });

    test('recordPending sanitizes url and headers when opted in', () {
      final session = InspectorSession(
        settings: const InterceptlySettings(
          redactedHeaders: _optInHeaders,
          redactedQueryParams: {'token'},
        ),
      );
      addTearDown(session.dispose);
      session.recordPending(
        id: 'opt-in',
        method: 'GET',
        url: 'https://api.example.com/items?token=abc&page=2',
        timestamp: DateTime(2026),
        requestHeaders: const {'Authorization': 'Bearer secret'},
      );
      final entry = session.entries.singleWhere((e) => e.id == 'opt-in');
      expect(entry.requestHeaders['Authorization'], '[REDACTED]');
      final uri = Uri.parse(entry.url);
      expect(uri.queryParameters['token'], '[REDACTED]');
      expect(uri.queryParameters['page'], '2');
    });

    test('record applies sanitize redact and bodyRedactor before isolate',
        () async {
      var calls = 0;
      final session = InspectorSession(
        settings: InterceptlySettings(
          redactedHeaders: _optInHeaders,
          redactedQueryParams: {'token'},
          bodyRedactor: (body) {
            calls++;
            return _bytes('x');
          },
        ),
      );
      addTearDown(session.dispose);
      await session.initialize();
      session.record(
        RawCapture(
          id: 'full-pipeline',
          method: 'POST',
          url: 'https://api.example.com/s?token=abc&page=1',
          requestHeaders: const {'Authorization': 'Bearer s'},
          responseHeaders: const {'Set-Cookie': 'c=1'},
          statusCode: 200,
          durationMs: 5,
          timestamp: DateTime(2026),
          requestBodyBytes: RawCapture.wrapBytes(_bytes('req')),
          responseBodyBytes: RawCapture.wrapBytes(_bytes('res')),
        ),
      );
      final entry = await _waitForEntry(session, 'full-pipeline');
      expect(calls, 2);
      expect(entry.requestHeaders['Authorization'], '[REDACTED]');
      expect(entry.responseHeaders['Set-Cookie'], '[REDACTED]');
      final uri = Uri.parse(entry.url);
      expect(uri.queryParameters['token'], '[REDACTED]');
      expect(uri.queryParameters['page'], '1');
      final record = await session.loadDetail(entry);
      expect(_text(record.requestBodyBytes), 'x');
      expect(_text(record.responseBodyBytes), 'x');
    });
  });
}
