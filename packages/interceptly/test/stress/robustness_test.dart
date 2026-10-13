import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/session/body_decode_service.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void _mockTempDir(Future<Object?> Function() handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, (call) async {
    if (call.method == 'getTemporaryDirectory') return handler();
    return null;
  });
}

Future<void> _waitFor(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

RawCapture _capture(
  String id, {
  String? url,
  String body = '{"ok":true}',
}) =>
    RawCapture(
      id: id,
      method: 'GET',
      url: url ?? 'https://api.example.com/$id',
      requestHeaders: const {},
      responseHeaders: const {'content-type': 'application/json'},
      statusCode: 200,
      durationMs: 1,
      timestamp: DateTime(2026),
      responseBodyBytes: RawCapture.wrapBytes(utf8.encode(body)),
      responseContentType: 'application/json',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('interceptly_robustness');
    _mockTempDir(() async => tempDir.path);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Session survives storage failures', () {
    test('failed init does not leak an unhandled error and can retry',
        () async {
      var fail = true;
      _mockTempDir(() async {
        if (fail) throw PlatformException(code: 'no_temp');
        return tempDir.path;
      });

      final session = InspectorSession();
      addTearDown(session.dispose);

      session.record(_capture('a'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      fail = false;
      await session.initialize();

      await _waitFor(() => session.entries.isNotEmpty);
      expect(session.entries.map((e) => e.id), contains('a'));
    });

    test('unwritable temp dir still captures and clear() completes', () async {
      final blocker = File('${tempDir.path}/not_a_dir')..writeAsStringSync('x');
      _mockTempDir(() async => blocker.path);

      final session = InspectorSession(
        settings: const InterceptlySettings(bodyOffloadThreshold: 4),
      );
      addTearDown(session.dispose);
      await session.initialize();

      session.record(_capture('a'));
      await _waitFor(() => session.entries.isNotEmpty);
      expect(session.entries.map((e) => e.id), contains('a'));

      final detail = await session.loadDetail(session.entries.first);
      expect(detail.responseBodyPreview, '{"ok":true}');

      await session.clear().timeout(const Duration(seconds: 3));
      expect(session.entries, isEmpty);
    });
  });

  group('BodyDecodeService', () {
    test('decodes text truncated in the middle of a multi-byte char', () async {
      final full = utf8.encode('{"msg":"Xin chào thế giới 🌍"}');
      final cut = Uint8List.fromList(full.sublist(0, full.length - 4));

      final text = await BodyDecodeService.decodeAsync(cut, 'application/json');
      expect(text, startsWith('{"msg":"Xin chào thế giới'));
    });

    test('still reports genuinely binary data as binary', () async {
      final bytes = Uint8List.fromList([0xff, 0xfe, 0x00, 0xc3, 0x28, 0xa0]);
      final text = await BodyDecodeService.decodeAsync(bytes, null);
      expect(BodyDecodeService.isPlaceholder(text!), isTrue);
    });
  });

  group('Security and Session settings', () {
    test('redacts configured sensitive headers case-insensitively', () async {
      final session = InspectorSession(
        settings: const InterceptlySettings(
          redactedHeaders: {'authorization', 'x-api-key', 'cookie'},
        ),
      );
      addTearDown(session.dispose);

      session.recordPending(
        id: 'pend_1',
        method: 'GET',
        url: 'https://example.com/test',
        timestamp: DateTime(2026),
        requestHeaders: {
          'Authorization': 'Bearer secret_token',
          'X-API-KEY': '12345',
          'content-type': 'application/json',
        },
      );

      final entry = session.entries.first;
      expect(entry.requestHeaders['Authorization'], '[REDACTED]');
      expect(entry.requestHeaders['X-API-KEY'], '[REDACTED]');
      expect(entry.requestHeaders['content-type'], 'application/json');
    });

    test('shouldCapture ignores matching requests completely', () async {
      final session = InspectorSession(
        settings: InterceptlySettings(
          shouldCapture: (url) => !url.contains('/sensitive'),
        ),
      );
      addTearDown(session.dispose);

      session.recordPending(
        id: '1',
        method: 'GET',
        url: 'https://example.com/sensitive/data',
        timestamp: DateTime(2026),
      );
      expect(session.entries, isEmpty);

      session.record(
        _capture('2', url: 'https://example.com/sensitive/data'),
      );
      expect(session.entries, isEmpty);

      session.recordPending(
        id: '3',
        method: 'GET',
        url: 'https://example.com/public/data',
        timestamp: DateTime(2026),
      );
      expect(session.entries.length, 1);
    });

    test('multiple sessions have distinct sessionIds and do not collide',
        () async {
      final s1 = InspectorSession();
      final s2 = InspectorSession();
      addTearDown(s1.dispose);
      addTearDown(s2.dispose);

      expect(s1.sessionId, isNot(equals(s2.sessionId)));
    });
  });

  group('Interceptly.init single-entrypoint setup', () {
    test('Interceptly.init configures settings and target session', () async {
      final customSession = InspectorSession();
      addTearDown(customSession.dispose);
      final navKey = GlobalKey<NavigatorState>();

      await Interceptly.init(
        navigatorKey: navKey,
        session: customSession,
        settings: const InterceptlySettings(
          maxBodyBytes: 1024,
          redactedHeaders: {'custom-token'},
        ),
        showFloatingButton: false,
      );

      expect(customSession.settings.maxBodyBytes, 1024);
      expect(customSession.settings.redactedHeaders, contains('custom-token'));
    });

    test('Interceptly.init uses default settings when none provided', () async {
      final customSession = InspectorSession();
      addTearDown(customSession.dispose);
      final navKey = GlobalKey<NavigatorState>();

      await Interceptly.init(
        navigatorKey: navKey,
        session: customSession,
        showFloatingButton: false,
      );

      expect(customSession.settings.maxBodyBytes, 5 * 1024 * 1024);
      expect(customSession.settings.maxEntries, 5000);
    });
  });
}
