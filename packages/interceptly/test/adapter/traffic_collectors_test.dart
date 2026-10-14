import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/model/index_entry.dart';

const _channel = MethodChannel('plugins.flutter.io/path_provider');

Future<IndexEntry> _waitForEntry(InspectorSession session, String id) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(end)) {
    for (final entry in session.entries) {
      if (entry.id == id && entry is IndexEntry && entry.statusCode != 0) {
        return entry;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw StateError('entry $id never completed with non-zero status code');
}

Future<IndexEntry> _waitForFailedEntry(InspectorSession session, String id) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(end)) {
    for (final entry in session.entries) {
      if (entry.id == id && entry is IndexEntry && entry.hasError) {
        return entry;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw StateError('entry $id never completed with error');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    await InspectorSession.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp('collector_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tempDir.path;
      return null;
    });
  });

  tearDown(() async {
    await InspectorSession.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('DefaultHttpTrafficCollector', () {
    test('startRequest creates HttpRequestContext and records pending request in session', () async {
      final session = InspectorSession.instance;
      await session.initialize();

      final collector = DefaultHttpTrafficCollector();
      expect(collector.session, equals(session));

      final uri = Uri.parse('https://api.example.com/items');
      final bodyBytes = Uint8List.fromList([1, 2, 3, 4]);
      final headers = {'authorization': 'Bearer token', 'x-custom': 'val'};

      final context = await collector.startRequest(
        method: 'POST',
        uri: uri,
        headers: headers,
        bodyBytes: bodyBytes,
        contentType: 'application/json',
      );

      expect(context, isNotNull);
      expect(context!.method, equals('POST'));
      expect(context.uri, equals(uri));
      expect(context.url, equals('https://api.example.com/items'));
      expect(context.requestHeaders, equals(headers));
      expect(context.requestBodyBytes, equals(bodyBytes));
      expect(context.requestContentType, equals('application/json'));
      expect(context.id, isNotEmpty);

      // Verify pending entry in session memory index
      expect(session.entries.length, equals(1));
      final pending = session.entries.first;
      expect(pending.id, equals(context.id));
      expect(pending.method, equals('POST'));
      expect(pending.url, equals('https://api.example.com/items'));
      expect(pending.statusCode, equals(0));
    });

    test('startRequest respects custom requestId', () async {
      final session = InspectorSession.instance;
      await session.initialize();

      final collector = DefaultHttpTrafficCollector();
      final uri = Uri.parse('https://api.example.com/custom-id');

      final context = await collector.startRequest(
        method: 'GET',
        uri: uri,
        requestId: 'custom-req-1234',
      );

      expect(context, isNotNull);
      expect(context!.id, equals('custom-req-1234'));
      expect(session.entries.first.id, equals('custom-req-1234'));
    });

    test('startRequest returns null when session is disabled', () async {
      final session = InspectorSession.instance;
      await session.initialize();

      session.disable();
      expect(session.isEnabled, isFalse);

      final collector = DefaultHttpTrafficCollector();
      final context = await collector.startRequest(
        method: 'GET',
        uri: Uri.parse('https://api.example.com/disabled'),
      );

      expect(context, isNull);
      expect(session.entries, isEmpty);
    });

    test('completeResponse calculates duration and records completed RawCapture into session', () async {
      final session = InspectorSession.instance;
      await session.initialize();

      final collector = DefaultHttpTrafficCollector();
      final uri = Uri.parse('https://api.example.com/success');

      final context = await collector.startRequest(
        method: 'GET',
        uri: uri,
      );
      expect(context, isNotNull);

      final responseBytes = Uint8List.fromList([10, 20, 30]);
      final responseHeaders = {'content-type': 'application/json', 'x-resp': 'ok'};

      await collector.completeResponse(
        context: context!,
        statusCode: 200,
        headers: responseHeaders,
        bodyBytes: responseBytes,
        responseContentType: 'application/json',
      );

      final entry = await _waitForEntry(session, context.id);
      expect(entry.id, equals(context.id));
      expect(entry.statusCode, equals(200));
      expect(entry.hasError, isFalse);
      expect(entry.durationMs, greaterThanOrEqualTo(0));
    });

    test('completeResponse respects explicit durationMs when provided', () async {
      final session = InspectorSession.instance;
      await session.initialize();

      final collector = DefaultHttpTrafficCollector();
      final uri = Uri.parse('https://api.example.com/explicit-duration');

      final context = await collector.startRequest(
        method: 'POST',
        uri: uri,
      );
      expect(context, isNotNull);

      await collector.completeResponse(
        context: context!,
        statusCode: 201,
        durationMs: 456,
      );

      final entry = await _waitForEntry(session, context.id);
      expect(entry.statusCode, equals(201));
      expect(entry.durationMs, equals(456));
    });

    test('failRequest records failed RawCapture with error details and duration', () async {
      final session = InspectorSession.instance;
      await session.initialize();

      final collector = DefaultHttpTrafficCollector();
      final uri = Uri.parse('https://api.example.com/failure');

      final context = await collector.startRequest(
        method: 'GET',
        uri: uri,
      );
      expect(context, isNotNull);

      final socketException = const SocketException('Connection refused');
      collector.failRequest(
        context: context!,
        error: socketException,
        errorType: 'SocketException',
        errorMessage: 'Connection refused',
      );

      final entry = await _waitForFailedEntry(session, context.id);
      expect(entry.id, equals(context.id));
      expect(entry.statusCode, equals(0));
      expect(entry.hasError, isTrue);
      expect(entry.errorType, equals('SocketException'));
      expect(entry.errorMessage, equals('Connection refused'));
      expect(entry.durationMs, greaterThanOrEqualTo(0));
    });

    test('failRequest infers errorType and errorMessage when omitted and respects custom statusCode', () async {
      final session = InspectorSession.instance;
      await session.initialize();

      final collector = DefaultHttpTrafficCollector();
      final uri = Uri.parse('https://api.example.com/server-error');

      final context = await collector.startRequest(
        method: 'POST',
        uri: uri,
      );
      expect(context, isNotNull);

      final httpError = FormatException('Invalid response syntax');
      collector.failRequest(
        context: context!,
        error: httpError,
        statusCode: 502,
        durationMs: 120,
      );

      final entry = await _waitForFailedEntry(session, context.id);
      expect(entry.id, equals(context.id));
      expect(entry.statusCode, equals(502));
      expect(entry.hasError, isTrue);
      expect(entry.errorType, equals('FormatException'));
      expect(entry.errorMessage, contains('Invalid response syntax'));
      expect(entry.durationMs, equals(120));
    });

    test('startRequest rethrows SimulatedNetworkException and records failure when offline simulation is active', () async {
      final session = InspectorSession.instance;
      await session.initialize();

      // Configure offline simulation
      session.setNetworkSimulation(
        NetworkSimulationProfile.offlineProfile,
      );

      final collector = DefaultHttpTrafficCollector();
      final uri = Uri.parse('https://api.example.com/offline-test');

      expect(
        () => collector.startRequest(
          method: 'GET',
          uri: uri,
        ),
        throwsA(isA<SimulatedNetworkException>()),
      );

      // Verify that the failed capture was recorded in session
      expect(session.entries.length, equals(1));
      final failedEntry = await _waitForFailedEntry(session, session.entries.first.id);
      expect(failedEntry.hasError, isTrue);
      expect(failedEntry.errorType, equals('SimulatedNetworkException'));
    });

    test('collector operations never throw unexpected errors outwards (guardCapture resilience)', () async {
      final session = InspectorSession.instance;
      await session.initialize();

      final collector = DefaultHttpTrafficCollector();
      final dummyContext = HttpRequestContext(
        id: 'dummy-resilience',
        method: 'GET',
        uri: Uri.parse('https://api.example.com/resilience'),
        startedAt: DateTime.now(),
      );

      // Even if session is disposed, collector completeResponse and failRequest should be safe
      await session.dispose();

      expect(
        () => collector.completeResponse(
          context: dummyContext,
          statusCode: 200,
        ),
        returnsNormally,
      );

      expect(
        () => collector.failRequest(
          context: dummyContext,
          error: Exception('Some error'),
        ),
        returnsNormally,
      );
    });
  });

  group('DefaultRealtimeTrafficCollector', () {
    test('recordConnection records WebSocket connection handshake in session', () async {
      final session = InspectorSession.instance;

      final collector = DefaultRealtimeTrafficCollector();
      expect(collector.session, equals(session));

      final uri = Uri.parse('wss://stream.example.com/feed');
      final headers = {'upgrade': 'websocket', 'sec-websocket-protocol': 'chat'};

      collector.recordConnection(
        sessionId: 'ws-conn-1',
        uri: uri,
        headers: headers,
      );

      expect(session.entries.length, equals(1));
      final entry = session.entries.first;
      expect(entry.id, equals('ws-conn-1'));
      expect(entry.method, equals('WS'));
      expect(entry.url, equals('wss://stream.example.com/feed'));
      expect(entry.statusCode, equals(0));
    });

    test('recordFrame records text frame with correct direction and payload into session buffer', () async {
      final session = InspectorSession.instance;

      final collector = DefaultRealtimeTrafficCollector();

      collector.recordFrame(
        sessionId: 'ws-frames-1',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        payload: '{"type":"greet","msg":"hello"}',
      );

      final frames = session.getRealtimeFrames('ws-frames-1');
      expect(frames.length, equals(1));
      expect(frames.first.sessionId, equals('ws-frames-1'));
      expect(frames.first.direction, equals(FrameDirection.incoming));
      expect(frames.first.type, equals(FrameType.text));
      expect(frames.first.textPayload, equals('{"type":"greet","msg":"hello"}'));
      expect(frames.first.payloadSizeBytes, greaterThan(0));
    });

    test('recordFrame records binary frame with Uint8List and List<int> payloads', () async {
      final session = InspectorSession.instance;

      final collector = DefaultRealtimeTrafficCollector();

      final uint8Bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      collector.recordFrame(
        sessionId: 'ws-binary-1',
        direction: FrameDirection.outgoing,
        type: FrameType.binary,
        payload: uint8Bytes,
      );

      final listIntBytes = <int>[10, 20, 30];
      collector.recordFrame(
        sessionId: 'ws-binary-1',
        direction: FrameDirection.incoming,
        type: FrameType.binary,
        payload: listIntBytes,
      );

      final frames = session.getRealtimeFrames('ws-binary-1');
      expect(frames.length, equals(2));

      expect(frames[0].direction, equals(FrameDirection.outgoing));
      expect(frames[0].type, equals(FrameType.binary));
      expect(frames[0].binaryPayload, equals(uint8Bytes));
      expect(frames[0].payloadSizeBytes, equals(5));

      expect(frames[1].direction, equals(FrameDirection.incoming));
      expect(frames[1].type, equals(FrameType.binary));
      expect(frames[1].binaryPayload, equals(Uint8List.fromList([10, 20, 30])));
      expect(frames[1].payloadSizeBytes, equals(3));
    });

    test('recordClose updates connection status with closeCode and closeReason', () async {
      final session = InspectorSession.instance;

      final collector = DefaultRealtimeTrafficCollector();
      collector.recordConnection(
        sessionId: 'ws-close-1',
        uri: Uri.parse('wss://echo.example.com'),
      );

      collector.recordClose(
        sessionId: 'ws-close-1',
        closeCode: 1001,
        closeReason: 'Going away',
      );

      expect(session.entries.length, equals(1));
      final entry = session.entries.first;
      expect(entry.statusCode, equals(1001));
      expect(entry.errorMessage, equals('Going away'));
      expect(entry.hasError, isTrue); // closeCode 1001 > 1000 is marked as error
    });

    test('recordClose defaults to closeCode 1000 when omitted', () async {
      final session = InspectorSession.instance;

      final collector = DefaultRealtimeTrafficCollector();
      collector.recordConnection(
        sessionId: 'ws-close-default',
        uri: Uri.parse('wss://echo.example.com'),
      );

      collector.recordClose(sessionId: 'ws-close-default');

      expect(session.entries.length, equals(1));
      final entry = session.entries.first;
      expect(entry.statusCode, equals(1000));
      expect(entry.hasError, isFalse);
    });

    test('realtime collector operations never throw when session is disposed', () {
      final session = InspectorSession.instance;
      session.dispose();

      final collector = DefaultRealtimeTrafficCollector();

      expect(
        () => collector.recordConnection(
          sessionId: 'ws-disposed',
          uri: Uri.parse('wss://example.com'),
        ),
        returnsNormally,
      );

      expect(
        () => collector.recordFrame(
          sessionId: 'ws-disposed',
          direction: FrameDirection.incoming,
          type: FrameType.text,
          payload: 'test',
        ),
        returnsNormally,
      );

      expect(
        () => collector.recordClose(sessionId: 'ws-disposed'),
        returnsNormally,
      );
    });
  });

  group('HttpCaptureAdapter and RealtimeCaptureAdapter contracts', () {
    test('adapter implementations fulfill contract interfaces', () {
      final session = InspectorSession.instance;

      final httpCollector = DefaultHttpTrafficCollector();
      final realtimeCollector = DefaultRealtimeTrafficCollector();

      final httpAdapter = _TestHttpCaptureAdapter(httpCollector, session);
      final realtimeAdapter = _TestRealtimeCaptureAdapter(realtimeCollector, session);

      expect(httpAdapter.collector, equals(httpCollector));
      expect(httpAdapter.session, equals(session));
      expect(realtimeAdapter.collector, equals(realtimeCollector));
      expect(realtimeAdapter.session, equals(session));
    });
  });
}

class _TestHttpCaptureAdapter implements HttpCaptureAdapter {
  _TestHttpCaptureAdapter(this.collector, this.session);

  @override
  final HttpTrafficCollector collector;

  @override
  final InspectorSession session;
}

class _TestRealtimeCaptureAdapter implements RealtimeCaptureAdapter {
  _TestRealtimeCaptureAdapter(this.collector, this.session);

  @override
  final RealtimeTrafficCollector collector;

  @override
  final InspectorSession session;
}
