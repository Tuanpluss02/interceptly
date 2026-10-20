import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';

class _FakeSender implements RealtimeConnectionSender {
  final RealtimeProtocolType _protocol;
  bool isConnected = true;
  final List<RealtimeMessageDraft> sentDrafts = [];

  _FakeSender({
    RealtimeProtocolType protocol = RealtimeProtocolType.webSocket,
  }) : _protocol = protocol;

  @override
  RealtimeProtocolType get protocolType => _protocol;

  @override
  bool get canSend => isConnected;

  @override
  Future<void> send(RealtimeMessageDraft draft) async {
    if (!canSend) {
      throw StateError('Cannot send when not connected');
    }
    sentDrafts.add(draft);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Interceptly.resetForTesting();
    RealtimeTrafficCollector.instance = DefaultRealtimeTrafficCollector();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
    RealtimeTrafficCollector.instance = DefaultRealtimeTrafficCollector();
  });

  group('DefaultRealtimeTrafficCollector connection and frame recording', () {
    test('recordConnection records WebSocket connection handshake in engine',
        () {
      final engine = InterceptlyEngine.instance;
      final collector = DefaultRealtimeTrafficCollector();
      expect(collector.engine, equals(engine));

      final uri = Uri.parse('wss://stream.example.com/feed');
      final headers = {
        'upgrade': 'websocket',
        'sec-websocket-protocol': 'chat',
      };

      collector.recordConnection(
        sessionId: 'ws-conn-1',
        uri: uri,
        headers: headers,
      );

      expect(engine.entries.length, equals(1));
      final entry = engine.entries.first;
      expect(entry.id, equals('ws-conn-1'));
      expect(entry.method, equals('WS'));
      expect(entry.url, equals('wss://stream.example.com/feed'));
      expect(entry.statusCode, equals(0));
    });

    test('recordConnection supports custom protocol types (SSE, Socket.IO)',
        () {
      final engine = InterceptlyEngine.instance;
      final collector = DefaultRealtimeTrafficCollector();

      collector.recordConnection(
        sessionId: 'sse-conn-1',
        uri: Uri.parse('https://example.com/events'),
        protocolType: RealtimeProtocolType.sse,
      );

      collector.recordConnection(
        sessionId: 'sio-conn-1',
        uri: Uri.parse('https://example.com/socket.io/'),
        protocolType: RealtimeProtocolType.socketIo,
      );

      expect(engine.entries.length, equals(2));
      final sseEntry = engine.byId('sse-conn-1');
      final sioEntry = engine.byId('sio-conn-1');

      expect(sseEntry, isNotNull);
      expect(sseEntry!.method, equals('SSE'));

      expect(sioEntry, isNotNull);
      expect(sioEntry!.method, equals('SIO'));
    });

    test('recordConnection respects shouldCapture filter', () {
      final engine = InterceptlyEngine.instance;
      engine.configure(
        InterceptlySettings(
          shouldCapture: (url) => url.contains('allowed'),
        ),
      );

      final collector = DefaultRealtimeTrafficCollector();

      collector.recordConnection(
        sessionId: 'ignored-1',
        uri: Uri.parse('wss://ignored.example.com'),
      );
      expect(engine.entries, isEmpty);

      collector.recordConnection(
        sessionId: 'allowed-1',
        uri: Uri.parse('wss://allowed.example.com'),
      );
      expect(engine.entries.length, equals(1));
    });

    test(
      'recordFrame records text frame with correct direction and payload into engine buffer',
      () {
        final engine = InterceptlyEngine.instance;
        final collector = DefaultRealtimeTrafficCollector();

        collector.recordFrame(
          sessionId: 'ws-frames-1',
          direction: FrameDirection.incoming,
          type: FrameType.text,
          payload: '{"type":"greet","msg":"hello"}',
        );

        final frames = engine.getRealtimeFrames('ws-frames-1');
        expect(frames.length, equals(1));
        expect(frames.first.sessionId, equals('ws-frames-1'));
        expect(frames.first.direction, equals(FrameDirection.incoming));
        expect(frames.first.type, equals(FrameType.text));
        expect(
          frames.first.textPayload,
          equals('{"type":"greet","msg":"hello"}'),
        );
        expect(frames.first.payloadSizeBytes, greaterThan(0));
      },
    );

    test(
      'recordFrame records binary frame with Uint8List and List<int> payloads',
      () {
        final engine = InterceptlyEngine.instance;
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

        final frames = engine.getRealtimeFrames('ws-binary-1');
        expect(frames.length, equals(2));

        expect(frames[0].direction, equals(FrameDirection.outgoing));
        expect(frames[0].type, equals(FrameType.binary));
        expect(frames[0].binaryPayload, equals(uint8Bytes));
        expect(frames[0].payloadSizeBytes, equals(5));

        expect(frames[1].direction, equals(FrameDirection.incoming));
        expect(frames[1].type, equals(FrameType.binary));
        expect(
          frames[1].binaryPayload,
          equals(Uint8List.fromList([10, 20, 30])),
        );
        expect(frames[1].payloadSizeBytes, equals(3));
      },
    );

    test('recordClose updates connection status with closeCode and closeReason',
        () {
      final engine = InterceptlyEngine.instance;
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

      expect(engine.entries.length, equals(1));
      final entry = engine.entries.first;
      expect(entry.statusCode, equals(1001));
      expect(entry.errorMessage, equals('Going away'));
      expect(entry.hasError, isTrue);
    });

    test('recordClose defaults to closeCode 1000 when omitted', () {
      final engine = InterceptlyEngine.instance;
      final collector = DefaultRealtimeTrafficCollector();

      collector.recordConnection(
        sessionId: 'ws-close-default',
        uri: Uri.parse('wss://echo.example.com'),
      );

      collector.recordClose(sessionId: 'ws-close-default');

      expect(engine.entries.length, equals(1));
      final entry = engine.entries.first;
      expect(entry.statusCode, equals(1000));
      expect(entry.hasError, isFalse);
    });

    test('realtime collector operations never throw when engine is disposed',
        () async {
      final engine = InterceptlyEngine.instance;
      await engine.dispose();

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

  group('RealtimeSessionScope openSession and Lifecycle', () {
    test('openSession returns RealtimeSessionScope and records connection', () {
      final engine = InterceptlyEngine.instance;
      final collector = DefaultRealtimeTrafficCollector();
      final uri = Uri.parse('wss://example.com/socket');

      final scope = collector.openSession(uri: uri);

      expect(scope.isClosed, isFalse);
      expect(scope.uri, equals(uri));
      expect(scope.sessionId, isNotEmpty);
      expect(engine.entries.length, equals(1));
      expect(engine.entries.first.id, equals(scope.sessionId));

      scope.send('hello');
      scope.receive('world');

      final frames = engine.getRealtimeFrames(scope.sessionId);
      expect(frames.length, equals(2));
      expect(frames[0].direction, equals(FrameDirection.outgoing));
      expect(frames[0].textPayload, equals('hello'));
      expect(frames[1].direction, equals(FrameDirection.incoming));
      expect(frames[1].textPayload, equals('world'));

      scope.close(code: 1000, reason: 'normal');
      expect(scope.isClosed, isTrue);

      scope.close();
      scope.send('after close');
      scope.receive('after close');
      expect(engine.getRealtimeFrames(scope.sessionId).length, equals(2));
    });

    test('openSession respects shouldCapture predicate', () {
      final engine = InterceptlyEngine.instance;
      engine.configure(
        InterceptlySettings(
          shouldCapture: (url) => url.contains('keep'),
        ),
      );

      final collector = DefaultRealtimeTrafficCollector();
      final scope = collector.openSession(
        uri: Uri.parse('wss://drop.example.com'),
      );

      expect(engine.entries, isEmpty);
      scope.send('untracked message');
      expect(engine.getRealtimeFrames(scope.sessionId), isEmpty);
    });
  });

  group('RealtimeSessionScope Sender', () {
    late DefaultRealtimeTrafficCollector collector;
    late InterceptlyEngine engine;

    setUp(() {
      engine = InterceptlyEngine();
      collector = DefaultRealtimeTrafficCollector(engine: engine);
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('attachSender, detachSender, and canSend lifecycle', () async {
      final scope = collector.openSession(sessionId: 's-1');
      expect(scope.canSend, isFalse);

      final sender = _FakeSender();
      scope.attachSender(sender);
      expect(scope.canSend, isTrue);

      const draft = RealtimeMessageDraft(payload: 'ping');
      await scope.sendToServer(draft);
      expect(sender.sentDrafts, contains(draft));

      sender.isConnected = false;
      expect(scope.canSend, isFalse);

      sender.isConnected = true;
      scope.detachSender();
      expect(scope.canSend, isFalse);
    });

    test('scope.close() detaches sender and disables sending', () async {
      final scope = collector.openSession(sessionId: 's-close');
      final sender = _FakeSender();
      scope.attachSender(sender);
      expect(scope.canSend, isTrue);

      scope.close();
      expect(scope.isClosed, isTrue);
      expect(scope.canSend, isFalse);

      expect(
        () => scope.sendToServer(const RealtimeMessageDraft(payload: 'test')),
        throwsStateError,
      );
    });
  });

  group('RealtimeTrafficCollector Message Transmission', () {
    late DefaultRealtimeTrafficCollector collector;
    late InterceptlyEngine engine;

    setUp(() {
      engine = InterceptlyEngine();
      collector = DefaultRealtimeTrafficCollector(engine: engine);
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('routes sendMessage to active session sender', () async {
      final scope = collector.openSession(
        sessionId: 'ws-session',
        protocolType: RealtimeProtocolType.webSocket,
      );
      final sender = _FakeSender();
      scope.attachSender(sender);

      expect(collector.canSend('ws-session'), isTrue);
      expect(collector.getSender('ws-session'), equals(sender));

      const draft = RealtimeMessageDraft(payload: 'hello world');
      await collector.sendMessage('ws-session', draft);
      expect(sender.sentDrafts, contains(draft));
    });

    test('sendMessage on unknown session throws StateError', () async {
      expect(collector.canSend('unknown'), isFalse);
      expect(collector.getSender('unknown'), isNull);

      expect(
        () => collector.sendMessage(
          'unknown',
          const RealtimeMessageDraft(payload: 'hello'),
        ),
        throwsStateError,
      );
    });

    test('recordClose unregisters active scope from collector', () {
      final scope = collector.openSession(sessionId: 'ws-close-test');
      final sender = _FakeSender();
      scope.attachSender(sender);
      expect(collector.canSend('ws-close-test'), isTrue);

      collector.recordClose(sessionId: 'ws-close-test');
      expect(collector.canSend('ws-close-test'), isFalse);
      expect(collector.getSender('ws-close-test'), isNull);
    });
  });

  group('InterceptlyEngine Realtime Sender Delegation', () {
    late InterceptlyEngine engine;
    late DefaultRealtimeTrafficCollector collector;

    setUp(() {
      engine = InterceptlyEngine();
      collector = DefaultRealtimeTrafficCollector(engine: engine);
      RealtimeTrafficCollector.instance = collector;
    });

    tearDown(() async {
      await engine.dispose();
      RealtimeTrafficCollector.instance = DefaultRealtimeTrafficCollector();
    });

    test(
      'delegates canSendRealtimeMessage and sendRealtimeMessage to collector',
      () async {
        final scope = collector.openSession(
          sessionId: 'session-delegated',
          protocolType: RealtimeProtocolType.socketIo,
        );
        final sender = _FakeSender(protocol: RealtimeProtocolType.socketIo);
        scope.attachSender(sender);

        expect(engine.canSendRealtimeMessage('session-delegated'), isTrue);
        expect(
          engine.getRealtimeProtocol('session-delegated'),
          equals(RealtimeProtocolType.socketIo),
        );

        const draft =
            RealtimeMessageDraft(event: 'chat', payload: {'msg': 'hi'});
        await engine.sendRealtimeMessage('session-delegated', draft);
        expect(sender.sentDrafts, contains(draft));
      },
    );
  });

  group('RealtimeSessionScope eventName propagation', () {
    late DefaultRealtimeTrafficCollector collector;
    late InterceptlyEngine engine;

    setUp(() {
      engine = InterceptlyEngine();
      collector = DefaultRealtimeTrafficCollector(engine: engine);
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('scope.send and scope.receive propagate eventName to recorded frames',
        () {
      final scope = collector.openSession(sessionId: 's-events');
      scope.send('hello event', eventName: 'chat_message');
      scope.receive('ack event', eventName: 'chat_ack');

      final frames = engine.getRealtimeFrames('s-events');
      expect(frames.length, equals(2));
      expect(frames[0].direction, equals(FrameDirection.outgoing));
      expect(frames[0].eventName, equals('chat_message'));
      expect(frames[0].textPayload, equals('hello event'));

      expect(frames[1].direction, equals(FrameDirection.incoming));
      expect(frames[1].eventName, equals('chat_ack'));
      expect(frames[1].textPayload, equals('ack event'));
    });
  });

  group('Scope and Collector contracts', () {
    test('collector supports custom engine injection and global instance', () {
      final customEngine = InterceptlyEngine(
        settings: const InterceptlySettings(maxBodyBytes: 1234),
      );
      final realtimeCollector =
          DefaultRealtimeTrafficCollector(engine: customEngine);

      expect(realtimeCollector.engine, equals(customEngine));
      expect(realtimeCollector.maxBodyBytes, equals(1234));
      expect(
        RealtimeTrafficCollector.instance,
        isA<DefaultRealtimeTrafficCollector>(),
      );
    });
  });
}
