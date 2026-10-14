import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';

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
  group('RealtimeSessionScope Sender', () {
    late DefaultRealtimeTrafficCollector collector;
    late InspectorSession session;

    setUp(() {
      session = InspectorSession();
      collector = DefaultRealtimeTrafficCollector(session: session);
    });

    tearDown(() {
      session.dispose();
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

      // When sender is disconnected
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
    late InspectorSession session;

    setUp(() {
      session = InspectorSession();
      collector = DefaultRealtimeTrafficCollector(session: session);
    });

    tearDown(() {
      session.dispose();
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

    test('recordClose unregisters active scope from collector', () async {
      final scope = collector.openSession(sessionId: 'ws-close-test');
      final sender = _FakeSender();
      scope.attachSender(sender);
      expect(collector.canSend('ws-close-test'), isTrue);

      collector.recordClose(sessionId: 'ws-close-test');
      expect(collector.canSend('ws-close-test'), isFalse);
      expect(collector.getSender('ws-close-test'), isNull);
    });
  });

  group('InspectorSession Realtime Sender Delegation', () {
    late InspectorSession session;
    late DefaultRealtimeTrafficCollector collector;

    setUp(() {
      session = InspectorSession();
      collector = DefaultRealtimeTrafficCollector(session: session);
      RealtimeTrafficCollector.instance = collector;
    });

    tearDown(() {
      session.dispose();
    });

    test('delegates canSendRealtimeMessage and sendRealtimeMessage to collector', () async {
      final scope = collector.openSession(
        sessionId: 'session-delegated',
        protocolType: RealtimeProtocolType.socketIo,
      );
      final sender = _FakeSender(protocol: RealtimeProtocolType.socketIo);
      scope.attachSender(sender);

      expect(session.canSendRealtimeMessage('session-delegated'), isTrue);
      expect(
        session.getRealtimeProtocol('session-delegated'),
        equals(RealtimeProtocolType.socketIo),
      );

      const draft = RealtimeMessageDraft(event: 'chat', payload: {'msg': 'hi'});
      await session.sendRealtimeMessage('session-delegated', draft);
      expect(sender.sentDrafts, contains(draft));
    });
  });
}
