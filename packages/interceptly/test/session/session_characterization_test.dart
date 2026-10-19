// ignore_for_file: invalid_use_of_internal_member
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';

const MethodChannel _channel =
    MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    await Interceptly.resetForTesting();
    tempDir =
        await Directory.systemTemp.createTemp('session_characterization_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tempDir.path;
      return null;
    });
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('InterceptlyEngine characterization', () {
    test('record to loadDetail and loadDetailById lifecycle', () async {
      final session = InterceptlyEngine();
      addTearDown(session.dispose);
      await session.initialize();

      final payload = utf8.encode('{"message":"hello"}');
      session.record(
        RawCapture(
          id: 'char-1',
          method: 'POST',
          url: 'https://example.com/api/test',
          requestHeaders: const {'content-type': 'application/json'},
          responseHeaders: const {'content-type': 'application/json'},
          statusCode: 200,
          durationMs: 42,
          timestamp: DateTime(2026),
          responseBodyBytes: RawCapture.wrapBytes(payload),
          responseContentType: 'application/json',
        ),
      );

      final end = DateTime.now().add(const Duration(seconds: 10));
      while (session.entries.isEmpty) {
        if (DateTime.now().isAfter(end)) {
          throw StateError('entry never arrived');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(session.entries.length, 1);
      final entry = session.entries.first;
      expect(entry.id, 'char-1');

      final recordFromDeprecated = await session.loadDetail(entry);
      expect(recordFromDeprecated.id, 'char-1');
      expect(recordFromDeprecated.responseBodyPreview, '{"message":"hello"}');

      final recordFromId = await session.loadDetailById('char-1');
      expect(recordFromId.id, 'char-1');
      expect(recordFromId.responseBodyPreview, '{"message":"hello"}');

      await session.clear();
      expect(session.entries, isEmpty);
      expect(session.totalEntries, 0);
    });

    test('recordPending times out with TimeoutException', () {
      fakeAsync((async) {
        final session = InterceptlyEngine(
          settings: const InterceptlySettings(
            pendingTimeout: Duration(seconds: 2),
          ),
        );
        addTearDown(session.dispose);

        session.recordPending(
          id: 'pending-1',
          method: 'GET',
          url: 'https://example.com/slow',
          timestamp: DateTime(2026),
        );

        expect(session.entries.length, 1);
        expect(session.entries.first.statusCode, 0);
        expect(session.entries.first.hasError, isFalse);

        async.elapse(const Duration(seconds: 1));
        expect(session.entries.first.hasError, isFalse);

        async.elapse(const Duration(seconds: 2));
        expect(session.entries.first.hasError, isTrue);
        expect(session.entries.first.errorType, 'TimeoutException');
      });
    });

    test('realtime connection, frame recording, and clear', () {
      fakeAsync((async) {
        final session = InterceptlyEngine();
        addTearDown(session.dispose);

        session.recordRealtimeConnection(
          id: 'ws-char',
          url: 'wss://echo.example.com',
          headers: {'Authorization': 'Bearer token'},
        );

        expect(session.entries.length, 1);
        expect(session.entries.first.method, 'WS');

        session.recordRealtimeFrame(
          RealtimeFrame.text(
            id: 'ws-frame-1',
            sessionId: 'ws-char',
            direction: FrameDirection.incoming,
            text: 'ping',
          ),
        );

        async.elapse(const Duration(milliseconds: 150));

        final frames = session.getRealtimeFrames('ws-char');
        expect(frames.length, 1);
        expect(frames.first.textPayload, 'ping');

        session.closeRealtimeConnection('ws-char', closeCode: 1000);
        expect(session.entries.first.statusCode, 1000);
        expect(session.entries.first.hasError, isFalse);

        session.clear();
        expect(session.getRealtimeFrames('ws-char'), isEmpty);
        expect(session.entries, isEmpty);
      });
    });
  });
}
