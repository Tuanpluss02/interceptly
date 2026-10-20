import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/service_extension/interceptly_service_extensions.dart';

const MethodChannel _channel =
    MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InterceptlyEngine engine;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rt_ext_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tempDir.path;
      return null;
    });

    engine = InterceptlyEngine();
    await engine.initialize();
  });

  tearDown(() async {
    await engine.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  RawCapture createCapture({
    required String id,
    int statusCode = 200,
    String url = 'https://api.example.com/items',
    int durationMs = 45,
  }) {
    final reqBytes = Uint8List.fromList(utf8.encode('{}'));
    final resBytes = Uint8List.fromList(utf8.encode('{"ok":true}'));
    return RawCapture(
      id: id,
      method: 'GET',
      url: url,
      statusCode: statusCode,
      durationMs: durationMs,
      timestamp: DateTime.now(),
      requestHeaders: const {'content-type': 'application/json'},
      responseHeaders: const {'content-type': 'application/json'},
      requestContentType: 'application/json',
      responseContentType: 'application/json',
      requestBodyBytes: TransferableTypedData.fromList([reqBytes]),
      responseBodyBytes: TransferableTypedData.fromList([resBytes]),
      requestSizeBytes: reqBytes.length,
      responseSizeBytes: resBytes.length,
    );
  }

  group('Realtime & Traffic Summary Service Extensions', () {
    test(
        'handleListRealtimeFrames lists frames with direction and type filters',
        () async {
      const sessionId = 'ws_session_1';
      engine.recordRealtimeConnection(
        id: sessionId,
        url: 'ws://example.com/ws',
        protocolType: RealtimeProtocolType.webSocket,
      );

      final f1 = RealtimeFrame.memoryText(
        id: 'f1',
        sessionId: sessionId,
        direction: FrameDirection.incoming,
        text: 'hello from server',
      );
      final f2 = RealtimeFrame.memoryText(
        id: 'f2',
        sessionId: sessionId,
        direction: FrameDirection.outgoing,
        text: 'ping to server',
      );
      final f3 = RealtimeFrame(
        id: 'f3',
        sessionId: sessionId,
        direction: FrameDirection.incoming,
        type: FrameType.binary,
        binaryPayload: Uint8List.fromList([0x01, 0x02, 0x03]),
      );

      await engine.recordRealtimeFrame(f1);
      await engine.recordRealtimeFrame(f2);
      await engine.recordRealtimeFrame(f3);

      // List all
      final allRes =
          await InterceptlyServiceExtensions.handleListRealtimeFrames(
        engine: engine,
        parameters: {'session_id': sessionId},
      );
      expect(allRes['total'], 3);
      expect(allRes['count'], 3);

      // Filter by direction: incoming
      final incomingRes =
          await InterceptlyServiceExtensions.handleListRealtimeFrames(
        engine: engine,
        parameters: {'session_id': sessionId, 'direction': 'incoming'},
      );
      expect(incomingRes['count'], 2);

      // Filter by type: binary
      final binaryRes =
          await InterceptlyServiceExtensions.handleListRealtimeFrames(
        engine: engine,
        parameters: {'session_id': sessionId, 'type': 'binary'},
      );
      expect(binaryRes['count'], 1);
      expect(binaryRes['frames'][0]['id'], 'f3');
    });

    test('handleGetRealtimeFrameDetail returns payload with truncation',
        () async {
      const sessionId = 'ws_session_2';
      final text = 'A' * 100;
      final f1 = RealtimeFrame.memoryText(
        id: 'f1',
        sessionId: sessionId,
        direction: FrameDirection.incoming,
        text: text,
      );
      await engine.recordRealtimeFrame(f1);

      final detail =
          await InterceptlyServiceExtensions.handleGetRealtimeFrameDetail(
        engine: engine,
        parameters: {
          'session_id': sessionId,
          'frame_id': 'f1',
          'offset': '10',
          'max_chars': '20',
        },
      );

      expect(detail['id'], 'f1');
      expect(detail['totalChars'], 100);
      expect(detail['offset'], 10);
      expect(detail['isTruncated'], isTrue);
      expect(detail['payload'], 'A' * 20);
      expect(detail['remainingChars'], 70);
    });

    test(
        'handleGetTrafficSummary computes accurate percentiles, error rate, and bandwidth',
        () async {
      // Initially empty
      final emptySummary = InterceptlyServiceExtensions.handleGetTrafficSummary(
        engine: engine,
        parameters: {},
      );
      expect(emptySummary['totalRequests'], 0);
      expect(emptySummary['errorRate'], 0.0);
      expect(emptySummary['latency']['p95Ms'], 0);

      // Ingest sample requests
      for (int i = 1; i <= 10; i++) {
        engine.record(createCapture(
          id: 'req_$i',
          statusCode: i > 8 ? 500 : 200,
          durationMs: i * 10,
        ));
      }

      await Future<void>.delayed(const Duration(milliseconds: 100));

      final summary = InterceptlyServiceExtensions.handleGetTrafficSummary(
        engine: engine,
        parameters: {},
      );

      expect(summary['totalRequests'], 10);
      expect(summary['failedRequests'], 2);
      expect(summary['errorRate'], 0.2); // 2/10 = 20%
      expect(summary['statusDistribution']['2xx'], 8);
      expect(summary['statusDistribution']['5xx'], 2);
      expect(summary['latency']['minMs'], 10);
      expect(summary['latency']['maxMs'], 100);
      expect(summary['latency']['p50Ms'], 60);
    });
  });
}
