// ignore_for_file: invalid_use_of_internal_member

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly_socket_io/interceptly_socket_io.dart';

import 'test_helpers/fake_socket.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InterceptlyEngine engine;

  setUp(() async {
    await Interceptly.resetForTesting();
    tempDir =
        await Directory.systemTemp.createTemp('interceptly_socket_io_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      },
    );
    engine = InterceptlyEngine.instance;
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Session Initialization & URI Resolution', () {
    test('attach() opens a realtime session with RealtimeProtocolType.socketIo',
        () async {
      final socket = FakeSocket(uri: 'http://localhost:3000');
      final tracker = InterceptlySocketIo.attach(
        socket,
        sessionId: 'session-init-1',
        headers: {'Authorization': 'Bearer secret-token'},
      );

      expect(tracker.isDetached, isFalse);
      expect(tracker.socket, equals(socket));
      expect(tracker.scope.sessionId, equals('session-init-1'));
      expect(tracker.scope.protocolType, equals(RealtimeProtocolType.socketIo));
      expect(tracker.scope.isClosed, isFalse);

      expect(engine.entries.length, equals(1));
      final entry = engine.entries.first;
      expect(entry.id, equals('session-init-1'));
      expect(entry.method, equals('SIO'));
      expect(entry.url, equals('http://localhost:3000'));
      expect(entry.requestHeaders,
          equals({'Authorization': 'Bearer secret-token'}));
      expect(entry.statusCode, equals(0));
    });

    test('auto-generates sessionId when omitted', () {
      final socket = FakeSocket(uri: 'http://localhost:3000');
      final tracker = InterceptlySocketIo.attach(socket);

      expect(tracker.scope.sessionId, isNotEmpty);
      expect(engine.entries.length, equals(1));
      expect(engine.entries.first.id, equals(tracker.scope.sessionId));
    });

    test('uses explicit uri when provided', () {
      final socket = FakeSocket(uri: 'http://localhost:3000');
      final explicitUri =
          Uri.parse('https://custom.backend.com/socket.io/?custom=1');

      final tracker = InterceptlySocketIo.attach(
        socket,
        uri: explicitUri,
        sessionId: 'explicit-uri-1',
      );

      expect(tracker.scope.uri, equals(explicitUri));
      expect(engine.entries.first.url, equals(explicitUri.toString()));
    });

    test('resolves URI with custom namespace', () {
      final socket = FakeSocket(
        uri: 'http://localhost:3000',
        nsp: '/chat',
      );

      final tracker = InterceptlySocketIo.attach(
        socket,
        sessionId: 'nsp-uri-1',
      );

      expect(
          tracker.scope.uri.toString(), equals('http://localhost:3000/chat'));
      expect(engine.entries.first.url, equals('http://localhost:3000/chat'));
    });

    test('falls back to default scheme and host when socket.io throws', () {
      final socket = FallbackFakeSocket(nsp: '/notifications');
      final tracker = InterceptlySocketIo.attach(
        socket,
        sessionId: 'fallback-uri-1',
      );

      expect(
        tracker.scope.uri.toString(),
        equals('http://socket-io/notifications'),
      );
      expect(
        engine.entries.first.url,
        equals('http://socket-io/notifications'),
      );
    });

    test(
        'extension method attachInterceptly() matches InterceptlySocketIo.attach()',
        () {
      final socket = FakeSocket(uri: 'http://localhost:4000');
      final tracker = socket.attachInterceptly(
        sessionId: 'ext-session-1',
        headers: {'X-Client': 'Flutter'},
      );

      expect(tracker, isA<InterceptlySocketIoTracker>());
      expect(tracker.scope.sessionId, equals('ext-session-1'));
      expect(tracker.scope.protocolType, equals(RealtimeProtocolType.socketIo));
      expect(engine.entries.first.url, equals('http://localhost:4000'));
      expect(
          engine.entries.first.requestHeaders, equals({'X-Client': 'Flutter'}));
    });
  });

  group('Incoming Traffic Capture', () {
    test(
        'captures incoming events via onAny with correct eventName and map payload',
        () async {
      final socket = FakeSocket();
      InterceptlySocketIo.attach(socket, sessionId: 'inc-map-1');

      socket.triggerIncomingEvent('chat:message', {
        'user': 'alice',
        'message': 'Hello from Socket.IO!',
      });
      await pumpEventQueue();

      final frames = engine.getRealtimeFrames('inc-map-1');
      expect(frames.length, equals(1));
      final frame = frames.first;
      expect(frame.direction, equals(FrameDirection.incoming));
      expect(frame.type, equals(FrameType.text));
      expect(frame.eventName, equals('chat:message'));
      expect(frame.textPayload, contains('"user":"alice"'));
      expect(frame.textPayload, contains('"message":"Hello from Socket.IO!"'));
    });

    test('captures incoming events with primitive string payload', () async {
      final socket = FakeSocket();
      InterceptlySocketIo.attach(socket, sessionId: 'inc-primitive-1');

      socket.triggerIncomingEvent('system:alert', 'Service rebooting in 5m');
      await pumpEventQueue();

      final frames = engine.getRealtimeFrames('inc-primitive-1');
      expect(frames.length, equals(1));
      final frame = frames.first;
      expect(frame.direction, equals(FrameDirection.incoming));
      expect(frame.type, equals(FrameType.text));
      expect(frame.eventName, equals('system:alert'));
      expect(frame.textPayload, equals('Service rebooting in 5m'));
    });

    test('handles events with no payload (single string argument)', () async {
      final socket = FakeSocket();
      InterceptlySocketIo.attach(socket, sessionId: 'inc-empty-1');

      socket.triggerIncomingEvent('ping');
      await pumpEventQueue();

      final frames = engine.getRealtimeFrames('inc-empty-1');
      expect(frames.length, equals(1));
      final frame = frames.first;
      expect(frame.direction, equals(FrameDirection.incoming));
      expect(frame.eventName, equals('ping'));
      expect(frame.textPayload, equals(''));
    });

    test('handles variadic / multi-argument payloads', () async {
      final socket = FakeSocket();
      InterceptlySocketIo.attach(socket, sessionId: 'inc-multi-1');

      socket.triggerIncomingVariadic('order:update', [
        'ORD-99',
        42,
        {'status': 'shipped'}
      ]);
      await pumpEventQueue();

      final frames = engine.getRealtimeFrames('inc-multi-1');
      expect(frames.length, equals(1));
      final frame = frames.first;
      expect(frame.direction, equals(FrameDirection.incoming));
      expect(frame.eventName, equals('order:update'));
      expect(frame.textPayload, contains('ORD-99'));
      expect(frame.textPayload, contains('42'));
      expect(frame.textPayload, contains('shipped'));
    });

    test(
        'handles large variadic argument list (> 10 arguments) without arity error',
        () async {
      final socket = FakeSocket();
      InterceptlySocketIo.attach(socket, sessionId: 'inc-multi-large');

      final largeArgs = List.generate(15, (i) => 'val_$i');
      expect(() => socket.triggerIncomingVariadic('stats:large', largeArgs),
          returnsNormally);
      await pumpEventQueue();

      final frames = engine.getRealtimeFrames('inc-multi-large');
      expect(frames.length, equals(1));
      expect(frames.first.eventName, equals('stats:large'));
      expect(frames.first.textPayload, equals(jsonEncode(largeArgs)));
    });

    test('preserves trailing null argument in multi-argument event', () async {
      final socket = FakeSocket();
      InterceptlySocketIo.attach(socket, sessionId: 'inc-multi-null');

      socket.triggerIncomingVariadic('item:update', ['item-1', null]);
      await pumpEventQueue();

      final frames = engine.getRealtimeFrames('inc-multi-null');
      expect(frames.length, equals(1));
      expect(frames.first.eventName, equals('item:update'));
      expect(frames.first.textPayload, equals(jsonEncode(['item-1', null])));
    });

    test('handles binary payloads (Uint8List)', () async {
      final socket = FakeSocket();
      InterceptlySocketIo.attach(socket, sessionId: 'inc-bin-1');

      final binaryData = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      socket.triggerIncomingEvent('file:chunk', binaryData);
      await pumpEventQueue();

      final frames = engine.getRealtimeFrames('inc-bin-1');
      expect(frames.length, equals(1));
      final frame = frames.first;
      expect(frame.direction, equals(FrameDirection.incoming));
      expect(frame.type, equals(FrameType.binary));
      expect(frame.eventName, equals('file:chunk'));
      expect(frame.binaryPayload, equals(binaryData));
      expect(frame.payloadSizeBytes, equals(4));
    });
  });

  group('Outgoing Traffic Capture', () {
    test(
        'captures outgoing events via onAnyOutgoing with correct eventName and payload',
        () async {
      final socket = FakeSocket();
      InterceptlySocketIo.attach(socket, sessionId: 'out-map-1');

      socket.emit('chat:send', {
        'to': 'bob',
        'message': 'Hi Bob!',
      });
      await pumpEventQueue();

      final frames = engine.getRealtimeFrames('out-map-1');
      expect(frames.length, equals(1));
      final frame = frames.first;
      expect(frame.direction, equals(FrameDirection.outgoing));
      expect(frame.type, equals(FrameType.text));
      expect(frame.eventName, equals('chat:send'));
      expect(frame.textPayload, contains('"to":"bob"'));
      expect(frame.textPayload, contains('"message":"Hi Bob!"'));
    });

    test('captures outgoing events with primitive string payload', () async {
      final socket = FakeSocket();
      InterceptlySocketIo.attach(socket, sessionId: 'out-primitive-1');

      socket.emit('status:update', 'available');
      await pumpEventQueue();

      final frames = engine.getRealtimeFrames('out-primitive-1');
      expect(frames.length, equals(1));
      final frame = frames.first;
      expect(frame.direction, equals(FrameDirection.outgoing));
      expect(frame.type, equals(FrameType.text));
      expect(frame.eventName, equals('status:update'));
      expect(frame.textPayload, equals('available'));
    });

    test('handles outgoing events with no payload', () async {
      final socket = FakeSocket();
      InterceptlySocketIo.attach(socket, sessionId: 'out-empty-1');

      socket.emit('heartbeat');
      await pumpEventQueue();

      final frames = engine.getRealtimeFrames('out-empty-1');
      expect(frames.length, equals(1));
      final frame = frames.first;
      expect(frame.direction, equals(FrameDirection.outgoing));
      expect(frame.eventName, equals('heartbeat'));
      expect(frame.textPayload, equals(''));
    });

    test('handles outgoing variadic / multi-argument payloads', () async {
      final socket = FakeSocket();
      InterceptlySocketIo.attach(socket, sessionId: 'out-multi-1');

      socket.emitVariadic('user:action', ['login', '127.0.0.1', 200]);
      await pumpEventQueue();

      final frames = engine.getRealtimeFrames('out-multi-1');
      expect(frames.length, equals(1));
      final frame = frames.first;
      expect(frame.direction, equals(FrameDirection.outgoing));
      expect(frame.eventName, equals('user:action'));
      expect(frame.textPayload, contains('login'));
      expect(frame.textPayload, contains('127.0.0.1'));
      expect(frame.textPayload, contains('200'));
    });

    test('handles outgoing binary payloads (Uint8List)', () async {
      final socket = FakeSocket();
      InterceptlySocketIo.attach(socket, sessionId: 'out-bin-1');

      final binaryData = Uint8List.fromList([10, 20, 30, 40, 50]);
      socket.emit('binary:upload', binaryData);
      await pumpEventQueue();

      final frames = engine.getRealtimeFrames('out-bin-1');
      expect(frames.length, equals(1));
      final frame = frames.first;
      expect(frame.direction, equals(FrameDirection.outgoing));
      expect(frame.type, equals(FrameType.binary));
      expect(frame.eventName, equals('binary:upload'));
      expect(frame.binaryPayload, equals(binaryData));
      expect(frame.payloadSizeBytes, equals(5));
    });
  });

  group('Connection Lifecycle', () {
    test('updates session state on connect and disconnect', () async {
      final socket = FakeSocket();
      final tracker =
          InterceptlySocketIo.attach(socket, sessionId: 'lifecycle-1');

      expect(tracker.scope.isClosed, isFalse);
      expect(engine.entries.first.statusCode, equals(0));

      socket.triggerConnect('socket-conn-123');
      await pumpEventQueue();
      expect(tracker.scope.isClosed, isFalse);

      socket.triggerDisconnect('transport close');
      await pumpEventQueue();

      expect(tracker.scope.isClosed, isTrue);
      expect(engine.entries.first.statusCode, equals(1000));
      expect(engine.entries.first.hasError, isFalse);
      expect(engine.entries.first.errorMessage, equals('transport close'));
      expect(engine.entries.first.durationMs, isNotNull);
    });

    test('records connect_error as frame and keeps session open', () async {
      final socket = FakeSocket();
      final tracker =
          InterceptlySocketIo.attach(socket, sessionId: 'conn-err-1');

      socket.triggerConnectError('xhr poll error');
      await pumpEventQueue();

      expect(tracker.scope.isClosed, isFalse);
      final frames = engine.getRealtimeFrames('conn-err-1');
      expect(frames.length, equals(1));
      expect(frames.first.eventName, equals('connect_error'));
      expect(frames.first.textPayload, contains('xhr poll error'));
    });

    test(
        'socket reconnection creates new active session and continues capturing',
        () async {
      final socket = FakeSocket();
      final tracker =
          InterceptlySocketIo.attach(socket, sessionId: 'reconnect-1');

      socket.triggerIncomingEvent('msg:1', 'first session');
      await pumpEventQueue();
      expect(tracker.scope.isClosed, isFalse);

      socket.triggerDisconnect('network down');
      await pumpEventQueue();
      expect(tracker.scope.isClosed, isTrue);

      socket.triggerConnect('new-sid-456');
      await pumpEventQueue();
      expect(tracker.scope.isClosed, isFalse);
      expect(tracker.scope.sessionId, isNot(equals('reconnect-1')));

      socket.triggerIncomingEvent('msg:2', 'second session');
      await pumpEventQueue();
      expect(tracker.scope.isClosed, isFalse);

      final newFrames = engine.getRealtimeFrames(tracker.scope.sessionId);
      expect(newFrames.length, equals(1));
      expect(newFrames.first.eventName, equals('msg:2'));
      expect(newFrames.first.textPayload, equals('second session'));
    });
  });

  group('Detachment & Idempotency', () {
    test('detach() removes listeners and stops capturing new events', () async {
      final socket = FakeSocket();
      final tracker = InterceptlySocketIo.attach(socket, sessionId: 'detach-1');

      socket.triggerIncomingEvent('msg1', 'before-detach');
      socket.emit('msg2', 'before-detach');
      await pumpEventQueue();

      expect(engine.getRealtimeFrames('detach-1').length, equals(2));

      tracker.detach();
      expect(tracker.isDetached, isTrue);

      socket.triggerIncomingEvent('msg1', 'after-detach');
      socket.emit('msg2', 'after-detach');
      socket.triggerDisconnect('should not close scope via tracker');
      await pumpEventQueue();

      expect(engine.getRealtimeFrames('detach-1').length, equals(2));
      expect(tracker.scope.isClosed, isTrue);
    });

    test('detach() is idempotent and safe to call multiple times', () {
      final socket = FakeSocket();
      final tracker =
          InterceptlySocketIo.attach(socket, sessionId: 'detach-idempotent');

      expect(() {
        tracker.detach();
        tracker.detach();
        tracker.detach();
      }, returnsNormally);
      expect(tracker.isDetached, isTrue);
    });
  });

  group('Interactive Replay & SocketIoSender', () {
    test('attaches SocketIoSender with correct protocolType and canSend', () {
      final socket = FakeSocket();
      final tracker = InterceptlySocketIo.attach(socket, sessionId: 'sender-1');

      final sender = tracker.scope.sender;
      expect(sender, isNotNull);
      expect(sender, isA<SocketIoSender>());
      expect(sender!.protocolType, equals(RealtimeProtocolType.socketIo));
      expect(sender.canSend, isTrue);

      socket.connected = false;
      expect(sender.canSend, isFalse);
    });

    test('sender.send() emits event to socket with custom or default eventName',
        () async {
      final socket = FakeSocket();
      final tracker =
          InterceptlySocketIo.attach(socket, sessionId: 'sender-send-1');
      final sender = tracker.scope.sender!;

      await sender.send(RealtimeMessageDraft(
        event: 'custom:event',
        payload: {'key': 'val'},
      ));

      expect(socket.sentPackets.length, equals(1));
      expect(
          socket.sentPackets.first['data'],
          equals([
            'custom:event',
            {'key': 'val'}
          ]));

      await sender.send(RealtimeMessageDraft(
        payload: 'raw-string-payload',
      ));

      expect(socket.sentPackets.length, equals(2));
      expect(socket.sentPackets[1]['data'],
          equals(['message', 'raw-string-payload']));
    });

    test(
        'sender.send() throws StateError when socket is disconnected or session closed',
        () async {
      final socket = FakeSocket();
      final tracker =
          InterceptlySocketIo.attach(socket, sessionId: 'sender-err-1');
      final sender = tracker.scope.sender!;

      socket.connected = false;
      expect(
        () => sender.send(RealtimeMessageDraft(payload: 'test')),
        throwsStateError,
      );

      socket.connected = true;
      tracker.scope.close();
      expect(
        () => sender.send(RealtimeMessageDraft(payload: 'test')),
        throwsStateError,
      );
    });
  });

  group('Error Resilience & Guarding', () {
    test(
        'does not throw when closed session or collector throws during event handling',
        () async {
      final socket = FakeSocket();
      final tracker =
          InterceptlySocketIo.attach(socket, sessionId: 'guarded-1');

      tracker.scope.close();
      expect(tracker.scope.isClosed, isTrue);

      expect(() {
        socket.triggerIncomingEvent('event:after:close', 'data');
        socket.emit('event:after:close', 'data');
        socket.triggerDisconnect('already closed');
        socket.triggerConnectError('already closed');
      }, returnsNormally);
    });
  });
}
