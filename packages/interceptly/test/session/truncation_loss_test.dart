import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';
import 'package:interceptly/src/model/raw_capture.dart';
import 'package:interceptly/src/session/body_decode_service.dart';
import 'package:interceptly/src/session/inspector_session.dart';

const _channel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('truncation_loss_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'getTemporaryDirectory') {
        return tempDir.path;
      }
      return null;
    });

    final session = InspectorSession.instance;
    session.configureSession(
      const InterceptlySettings(
        maxBodyBytes: 100, // 100 bytes storage cap
      ),
    );
    await session.initialize();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    final session = InspectorSession.instance;
    session.clear();
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  test(
      'writer_isolate preserves original responseSizeBytes and detects storage truncation',
      () async {
    final session = InspectorSession.instance;

    // Simulate an adapter that pre-capped the stream to 100 bytes,
    // but the original stream was 500 bytes.
    final cappedBody = Uint8List(100);
    final capture = RawCapture(
      id: 'trunc-1',
      method: 'GET',
      url: 'https://api.example.com/large-file',
      requestHeaders: const {},
      responseHeaders: const {'content-type': 'application/octet-stream'},
      statusCode: 200,
      durationMs: 10,
      timestamp: DateTime.now(),
      responseBodyBytes: RawCapture.wrapBytes(cappedBody),
      responseSizeBytes: 500, // Original size
      responseContentType: 'application/octet-stream',
    );

    session.record(capture);

    final end = DateTime.now().add(const Duration(seconds: 5));
    while (session.entries.isEmpty && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(session.entries.length, equals(1));
    final entry = session.entries.first;

    // Verify responseSizeBytes is the original 500 bytes, NOT the capped 100 bytes
    expect(entry.responseSizeBytes, equals(500));

    // Verify truncation stage is storage
    expect(entry.responseTruncation.isTruncated, isTrue);
    expect(entry.responseTruncation.stage, equals(TruncationStage.storage));
    expect(entry.responseTruncation.originalBytes, equals(500));
    expect(entry.responseTruncation.retainedBytes, equals(100));
  });

  test(
      'truncate returns entire byte array unmodified when maxBody <= 0 (unlimited)',
      () {
    final payload = Uint8List.fromList(List.generate(100, (i) => i));
    expect(BodyDecodeService.truncate(payload, 0, 10), equals(payload));
    expect(BodyDecodeService.truncate(payload, -1, 10), equals(payload));
  });
}
