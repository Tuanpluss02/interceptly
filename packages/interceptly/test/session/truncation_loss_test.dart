// ignore_for_file: invalid_use_of_internal_member

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/body_decode_service.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';

const _channel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    await Interceptly.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp('truncation_loss_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'getTemporaryDirectory') {
        return tempDir.path;
      }
      return null;
    });

    final engine = InterceptlyEngine.instance;
    engine.configure(
      const InterceptlySettings(
        maxBodyBytes: 100, // 100 bytes storage cap
      ),
    );
    await engine.initialize();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    final engine = InterceptlyEngine.instance;
    await engine.clear();
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
    await Interceptly.resetForTesting();
  });

  test(
      'writer_isolate preserves original responseSizeBytes and detects storage truncation',
      () async {
    final engine = InterceptlyEngine.instance;

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

    engine.record(capture);

    final end = DateTime.now().add(const Duration(seconds: 5));
    while (engine.entries.isEmpty && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(engine.entries.length, equals(1));
    final entry = engine.entries.first;

    // Verify responseSizeBytes is the original 500 bytes, NOT the capped 100 bytes
    expect(entry.responseSizeBytes, equals(500));

    // Verify truncation stage is storage
    expect(entry.responseTruncation.isTruncated, isTrue);
    expect(entry.responseTruncation.stage, equals(TruncationStage.storage));
    expect(entry.responseTruncation.originalBytes, equals(500));
    expect(entry.responseTruncation.retainedBytes, equals(100));
  });

  test(
      'payload within maxBodyBytes does not trigger false positive storage truncation when length differs from responseSizeBytes',
      () async {
    final engine = InterceptlyEngine.instance;
    engine.configure(
      const InterceptlySettings(
        maxBodyBytes: 5 * 1024 * 1024, // 5 MB default
      ),
    );

    // Simulate a JSON response where Content-Length was 20480 (20 KB),
    // but re-encoded JSON body in RAM is 20150 bytes.
    final jsonBody = Uint8List(20150);
    final capture = RawCapture(
      id: 'no-trunc-1',
      method: 'GET',
      url: 'https://api.example.com/data',
      requestHeaders: const {},
      responseHeaders: const {
        'content-type': 'application/json',
        'content-length': '20480',
      },
      statusCode: 200,
      durationMs: 15,
      timestamp: DateTime.now(),
      responseBodyBytes: RawCapture.wrapBytes(jsonBody),
      responseSizeBytes: 20480, // Content-Length
      responseContentType: 'application/json',
    );

    engine.record(capture);

    final end = DateTime.now().add(const Duration(seconds: 5));
    while (engine.entries.isEmpty && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(engine.entries.length, equals(1));
    final entry = engine.entries.first;

    expect(entry.responseSizeBytes, equals(20480));
    expect(entry.responseTruncation.isTruncated, isFalse);
    expect(entry.responseTruncation.stage, equals(TruncationStage.none));
    expect(entry.responseTruncation.hasDataLoss, isFalse);
    expect(entry.hasDataLoss, isFalse);
  });

  test(
      'HEAD or 304 response with large content-length and empty body does not falsely report truncation',
      () async {
    final engine = InterceptlyEngine.instance;
    engine.configure(
      const InterceptlySettings(
        maxBodyBytes: 5 * 1024 * 1024, // 5 MB
      ),
    );

    final capture = RawCapture(
      id: 'head-1',
      method: 'HEAD',
      url: 'https://api.example.com/large-asset.zip',
      requestHeaders: const {},
      responseHeaders: const {
        'content-length': '10485760', // 10 MB
      },
      statusCode: 200,
      durationMs: 5,
      timestamp: DateTime.now(),
      responseBodyBytes: null,
      responseSizeBytes: 10485760,
    );

    engine.record(capture);

    final end = DateTime.now().add(const Duration(seconds: 5));
    while (engine.entries.isEmpty && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(engine.entries.length, equals(1));
    final entry = engine.entries.first;

    expect(entry.responseSizeBytes, equals(10485760));
    expect(entry.responseTruncation.isTruncated, isFalse);
    expect(entry.responseTruncation.stage, equals(TruncationStage.none));
    expect(entry.responseTruncation.hasDataLoss, isFalse);
    expect(entry.hasDataLoss, isFalse);
  });

  test('RawCapture.wrapBytes slices before TransferableTypedData allocation',
      () {
    final largeBytes = Uint8List(1000);
    final wrapped = RawCapture.wrapBytes(largeBytes, 100);
    expect(wrapped, isNotNull);
    final materialized = wrapped!.materialize().asUint8List();
    expect(materialized.length, equals(100));
  });

  test(
      'truncate returns entire byte array unmodified when maxBody <= 0 (unlimited)',
      () {
    final payload = Uint8List.fromList(List.generate(100, (i) => i));
    expect(BodyDecodeService.truncate(payload, 0, 10), equals(payload));
    expect(BodyDecodeService.truncate(payload, -1, 10), equals(payload));
  });
}
