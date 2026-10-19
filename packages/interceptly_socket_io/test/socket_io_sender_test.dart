import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_socket_io/interceptly_socket_io.dart';

import 'test_helpers/fake_socket.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    await Interceptly.resetForTesting();
    tempDir = await Directory.systemTemp
        .createTemp('interceptly_socket_io_sender_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      },
    );
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('SocketIoSender & Interactive Composer Replay', () {
    test(
        'sender sends RealtimeMessageDraft via socket.emit with draft.event and draft.payload',
        () async {
      final socket = FakeSocket();
      final scope = RealtimeTrafficCollector.instance.openSession(
        uri: Uri.parse('http://localhost:3000'),
        protocolType: RealtimeProtocolType.socketIo,
      );
      final sender = SocketIoSender(socket, scope);

      await sender.send(const RealtimeMessageDraft(
        event: 'chat:message',
        payload: {'user': 'alice', 'text': 'hello!'},
      ));

      expect(socket.sentPackets.length, equals(1));
      final packet = socket.sentPackets.first;
      expect(
        packet['data'],
        equals([
          'chat:message',
          {'user': 'alice', 'text': 'hello!'},
        ]),
      );
    });

    test(
        'sender canSend returns true when connected and false when disconnected or closed',
        () {
      final socket = FakeSocket();
      final scope = RealtimeTrafficCollector.instance.openSession(
        uri: Uri.parse('http://localhost:3000'),
        protocolType: RealtimeProtocolType.socketIo,
      );
      final sender = SocketIoSender(socket, scope);

      // Initially connected and scope open
      expect(sender.protocolType, equals(RealtimeProtocolType.socketIo));
      expect(sender.canSend, isTrue);

      // Socket disconnected
      socket.connected = false;
      expect(sender.canSend, isFalse);

      // Reconnect socket
      socket.connected = true;
      expect(sender.canSend, isTrue);

      // Scope closed
      scope.close();
      expect(scope.isClosed, isTrue);
      expect(sender.canSend, isFalse);

      // Even if socket is connected, closed scope means canSend is false
      expect(socket.connected, isTrue);
      expect(sender.canSend, isFalse);
    });

    test(
        'sender throws StateError when canSend is false (disconnected socket or closed scope)',
        () async {
      final socket = FakeSocket();
      final scope = RealtimeTrafficCollector.instance.openSession(
        uri: Uri.parse('http://localhost:3000'),
        protocolType: RealtimeProtocolType.socketIo,
      );
      final sender = SocketIoSender(socket, scope);

      // Disconnected socket
      socket.connected = false;
      expect(
        () => sender.send(const RealtimeMessageDraft(
          event: 'test:event',
          payload: 'data',
        )),
        throwsStateError,
      );

      // Reconnect socket, close scope
      socket.connected = true;
      scope.close();
      expect(
        () => sender.send(const RealtimeMessageDraft(
          event: 'test:event',
          payload: 'data',
        )),
        throwsStateError,
      );
    });

    test(
        'RealtimeSessionScope.sendToServer dispatches through attached sender to socket',
        () async {
      final socket = FakeSocket();
      final tracker = InterceptlySocketIo.attach(
        socket,
        sessionId: 'session-send-to-server-1',
      );

      expect(tracker.scope.sender, isNotNull);
      expect(tracker.scope.canSend, isTrue);

      await tracker.scope.sendToServer(const RealtimeMessageDraft(
        event: 'server:command',
        payload: {'action': 'refresh', 'scope': 'all'},
      ));

      expect(socket.sentPackets.length, equals(1));
      final packet = socket.sentPackets.first;
      expect(
        packet['data'],
        equals([
          'server:command',
          {'action': 'refresh', 'scope': 'all'},
        ]),
      );
    });

    test(
        "fallback event name 'message' is used when draft.event is null or empty",
        () async {
      final socket = FakeSocket();
      final scope = RealtimeTrafficCollector.instance.openSession(
        uri: Uri.parse('http://localhost:3000'),
        protocolType: RealtimeProtocolType.socketIo,
      );
      final sender = SocketIoSender(socket, scope);

      // Null event
      await sender.send(const RealtimeMessageDraft(
        payload: 'string-payload-null-event',
      ));

      expect(socket.sentPackets.length, equals(1));
      expect(
        socket.sentPackets.first['data'],
        equals(['message', 'string-payload-null-event']),
      );

      // Empty string event
      await sender.send(const RealtimeMessageDraft(
        event: '',
        payload: {'count': 42},
      ));

      expect(socket.sentPackets.length, equals(2));
      expect(
        socket.sentPackets[1]['data'],
        equals([
          'message',
          {'count': 42}
        ]),
      );
    });

    test('sender sends binary payload (Uint8List) cleanly', () async {
      final socket = FakeSocket();
      final scope = RealtimeTrafficCollector.instance.openSession(
        uri: Uri.parse('http://localhost:3000'),
        protocolType: RealtimeProtocolType.socketIo,
      );
      final sender = SocketIoSender(socket, scope);

      final binaryPayload = Uint8List.fromList([0x00, 0x01, 0x02, 0xFE, 0xFF]);
      await sender.send(RealtimeMessageDraft(
        event: 'binary:upload',
        payload: binaryPayload,
      ));

      expect(socket.sentPackets.length, equals(1));
      final packet = socket.sentPackets.first;
      expect(
        packet['data'],
        equals([
          'binary:upload',
          binaryPayload,
        ]),
      );
    });
  });
}
