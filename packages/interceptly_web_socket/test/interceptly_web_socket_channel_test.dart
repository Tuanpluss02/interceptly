import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/adapter.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_web_socket/interceptly_web_socket.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A controllable [WebSocketChannel] test double.
class FakeWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  final StreamController<dynamic> _streamController;
  final StreamController<dynamic> _sinkController;
  final Completer<void> _readyCompleter = Completer<void>();

  @override
  String? protocol;

  @override
  int? closeCode;

  @override
  String? closeReason;

  int? sinkCloseCode;
  String? sinkCloseReason;
  bool sinkClosed = false;
  final List<dynamic> sentData = [];
  final List<Object> sinkErrors = [];

  FakeWebSocketChannel({
    StreamController<dynamic>? streamController,
    StreamController<dynamic>? sinkController,
    this.protocol,
    this.closeCode,
    this.closeReason,
    bool autoReady = true,
  })  : _streamController = streamController ?? StreamController<dynamic>(),
        _sinkController = sinkController ?? StreamController<dynamic>() {
    if (autoReady) {
      _readyCompleter.complete();
    }
    _sinkController.stream.listen(
      sentData.add,
      onError: sinkErrors.add,
    );
  }

  void completeReadyError(Object error, [StackTrace? stackTrace]) {
    _readyCompleter.completeError(error, stackTrace);
  }

  @override
  Future<void> get ready => _readyCompleter.future;

  @override
  Stream get stream => _streamController.stream;

  @override
  late final WebSocketSink sink = _FakeWebSocketSink(this);

  void emitIncoming(dynamic data) => _streamController.add(data);

  void emitIncomingError(Object error, [StackTrace? stackTrace]) =>
      _streamController.addError(error, stackTrace);

  Future<void> closeServer({int? code, String? reason}) async {
    closeCode = code;
    closeReason = reason;
    await _streamController.close();
  }
}

class _FakeWebSocketSink implements WebSocketSink {
  final FakeWebSocketChannel _channel;

  _FakeWebSocketSink(this._channel);

  @override
  void add(dynamic data) {
    _channel._sinkController.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _channel._sinkController.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<dynamic> stream) {
    return _channel._sinkController.addStream(stream);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _channel.sinkCloseCode = closeCode;
    _channel.sinkCloseReason = closeReason;
    _channel.sinkClosed = true;
    await _channel._sinkController.close();
  }

  @override
  Future<void> get done => _channel._sinkController.done;
}

void main() {
  group('InterceptlyWebSocketChannel', () {
    late InspectorSession session;
    late FakeWebSocketChannel fakeChannel;

    setUp(() async {
      await InspectorSession.resetForTesting();
      session = InspectorSession.instance;
      fakeChannel = FakeWebSocketChannel(protocol: 'chat-v1');
    });

    tearDown(() async {
      await session.dispose();
      await InspectorSession.resetForTesting();
    });

    test('initializes with custom sessionId, uri, headers and getters',
        () async {
      final uri = Uri.parse('wss://example.com/socket');
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        uri: uri,
        sessionId: 'custom-session-1',
        headers: {'Authorization': 'Bearer test'},
      );

      expect(channel.sessionId, equals('custom-session-1'));
      expect(channel.uri, equals(uri));
      expect(channel.headers, equals({'Authorization': 'Bearer test'}));
      expect(channel.protocol, equals('chat-v1'));
      expect(channel.inner, equals(fakeChannel));
      await expectLater(channel.ready, completes);

      // Verify connection recorded in session
      expect(session.entries.length, equals(1));
      final entry = session.entries.first;
      expect(entry.id, equals('custom-session-1'));
      expect(entry.method, equals('WS'));
      expect(entry.url, equals('wss://example.com/socket'));
      expect(entry.requestHeaders, equals({'Authorization': 'Bearer test'}));
      expect(entry.statusCode, equals(0)); // Handshake pending
    });

    test('auto-generates sessionId and assigns fallback uri when omitted', () {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
      );

      expect(channel.sessionId, isNotEmpty);
      expect(channel.uri, equals(Uri(scheme: 'ws', host: 'unknown-socket')));
      expect(session.entries.length, equals(1));
      expect(session.entries.first.url, equals('ws://unknown-socket'));
    });

    test('captures outgoing text frame via sink.add', () async {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        sessionId: 'ws-out-text',
      );

      channel.sink.add('Hello, Server!');
      await pumpEventQueue();

      // Verified forwarded to underlying socket
      expect(fakeChannel.sentData, equals(['Hello, Server!']));

      // Verified captured by Interceptly
      final frames = session.getRealtimeFrames('ws-out-text');
      expect(frames.length, equals(1));
      final frame = frames.first;
      expect(frame.sessionId, equals('ws-out-text'));
      expect(frame.direction, equals(FrameDirection.outgoing));
      expect(frame.type, equals(FrameType.text));
      expect(frame.textPayload, equals('Hello, Server!'));
      expect(frame.payloadSizeBytes, equals(14));
    });

    test('captures outgoing binary frame via sink.add', () async {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        sessionId: 'ws-out-bin',
      );

      final uint8Bytes = Uint8List.fromList([1, 2, 3, 4]);
      final plainList = <int>[5, 6, 7];

      channel.sink.add(uint8Bytes);
      channel.sink.add(plainList);
      await pumpEventQueue();

      expect(fakeChannel.sentData.length, equals(2));

      final frames = session.getRealtimeFrames('ws-out-bin');
      expect(frames.length, equals(2));

      expect(frames[0].direction, equals(FrameDirection.outgoing));
      expect(frames[0].type, equals(FrameType.binary));
      expect(frames[0].binaryPayload, equals(uint8Bytes));
      expect(frames[0].payloadSizeBytes, equals(4));

      expect(frames[1].direction, equals(FrameDirection.outgoing));
      expect(frames[1].type, equals(FrameType.binary));
      expect(frames[1].binaryPayload, equals(Uint8List.fromList([5, 6, 7])));
      expect(frames[1].payloadSizeBytes, equals(3));
    });

    test('captures incoming text frame via stream', () async {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        sessionId: 'ws-in-text',
      );

      final received = <dynamic>[];
      final sub = channel.stream.listen(received.add);

      fakeChannel.emitIncoming('Welcome to chat!');
      await pumpEventQueue();

      expect(received, equals(['Welcome to chat!']));

      final frames = session.getRealtimeFrames('ws-in-text');
      expect(frames.length, equals(1));
      final frame = frames.first;
      expect(frame.sessionId, equals('ws-in-text'));
      expect(frame.direction, equals(FrameDirection.incoming));
      expect(frame.type, equals(FrameType.text));
      expect(frame.textPayload, equals('Welcome to chat!'));

      await sub.cancel();
    });

    test('captures incoming binary frame via stream', () async {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        sessionId: 'ws-in-bin',
      );

      final received = <dynamic>[];
      final sub = channel.stream.listen(received.add);

      final bytes = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final plainList = <int>[0x01, 0x02];

      fakeChannel.emitIncoming(bytes);
      fakeChannel.emitIncoming(plainList);
      await pumpEventQueue();

      expect(received.length, equals(2));

      final frames = session.getRealtimeFrames('ws-in-bin');
      expect(frames.length, equals(2));

      expect(frames[0].direction, equals(FrameDirection.incoming));
      expect(frames[0].type, equals(FrameType.binary));
      expect(frames[0].binaryPayload, equals(bytes));

      expect(frames[1].direction, equals(FrameDirection.incoming));
      expect(frames[1].type, equals(FrameType.binary));
      expect(frames[1].binaryPayload, equals(Uint8List.fromList([0x01, 0x02])));

      await sub.cancel();
    });

    test('captures outgoing frames via sink.addStream', () async {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        sessionId: 'ws-stream-out',
      );

      final outgoingStream = Stream.fromIterable([
        'message 1',
        Uint8List.fromList([10, 20]),
        'message 2',
      ]);

      await channel.sink.addStream(outgoingStream);
      await pumpEventQueue();

      expect(fakeChannel.sentData.length, equals(3));

      final frames = session.getRealtimeFrames('ws-stream-out');
      expect(frames.length, equals(3));
      expect(frames[0].textPayload, equals('message 1'));
      expect(frames[1].binaryPayload, equals(Uint8List.fromList([10, 20])));
      expect(frames[2].textPayload, equals('message 2'));
    });

    test('records closeRealtimeConnection on sink.close', () async {
      final uri = Uri.parse('wss://example.com/close-test');
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        uri: uri,
        sessionId: 'ws-close-sink',
      );

      await channel.sink.close(1000, 'User logged out');
      await pumpEventQueue();

      expect(fakeChannel.sinkClosed, isTrue);
      expect(fakeChannel.sinkCloseCode, equals(1000));
      expect(fakeChannel.sinkCloseReason, equals('User logged out'));

      final entry = session.entries.firstWhere((e) => e.id == 'ws-close-sink');
      expect(entry.statusCode, equals(1000));
      expect(entry.errorMessage, equals('User logged out'));
    });

    test('records closeRealtimeConnection on server stream completion',
        () async {
      final uri = Uri.parse('wss://example.com/server-close-test');
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        uri: uri,
        sessionId: 'ws-close-server',
      );

      final completer = Completer<void>();
      channel.stream.listen((_) {}, onDone: completer.complete);

      await fakeChannel.closeServer(code: 1001, reason: 'Going away');
      await completer.future;
      await pumpEventQueue();

      final entry =
          session.entries.firstWhere((e) => e.id == 'ws-close-server');
      expect(entry.statusCode, equals(1001));
      expect(entry.errorMessage, equals('Going away'));
    });

    test('is idempotent: closing sink before stream done only records once',
        () async {
      final uri = Uri.parse('wss://example.com/idempotent-close');
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        uri: uri,
        sessionId: 'ws-idempotent',
      );

      final completer = Completer<void>();
      channel.stream.listen((_) {}, onDone: completer.complete);

      // Close client sink first
      await channel.sink.close(1000, 'Client closed');

      // Then server closes
      await fakeChannel.closeServer(code: 1006, reason: 'Abnormal');
      await completer.future;
      await pumpEventQueue();

      final entry = session.entries.firstWhere((e) => e.id == 'ws-idempotent');
      // Should retain client close status
      expect(entry.statusCode, equals(1000));
      expect(entry.errorMessage, equals('Client closed'));
    });

    test('propagates stream errors to subscriber', () async {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        sessionId: 'ws-err',
      );

      Object? receivedError;
      final sub = channel.stream.listen(
        (_) {},
        onError: (Object error) {
          receivedError = error;
        },
      );

      fakeChannel.emitIncomingError(StateError('Socket disconnect'));
      await pumpEventQueue();

      expect(receivedError, isA<StateError>());
      await sub.cancel();
    });

    test('propagates sink errors to underlying sink', () async {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        sessionId: 'ws-sink-err',
      );

      channel.sink.addError(const FormatException('Bad data'));
      await pumpEventQueue();

      expect(fakeChannel.sinkErrors.length, equals(1));
      expect(fakeChannel.sinkErrors.first, isA<FormatException>());
    });

    test('constructor creates functional InterceptlyWebSocketChannel',
        () async {
      final uri = Uri.parse('wss://example.com/wrapped');
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        uri: uri,
        sessionId: 'wrapped-id',
      );

      expect(channel, isA<InterceptlyWebSocketChannel>());
      expect(channel.sessionId, equals('wrapped-id'));
      expect(channel.uri, equals(uri));

      channel.sink.add('Wrapped ping');
      await pumpEventQueue();

      final frames = session.getRealtimeFrames('wrapped-id');
      expect(frames.length, equals(1));
      expect(frames.first.textPayload, equals('Wrapped ping'));
    });

    test('forwards getters: closeCode, closeReason, done', () async {
      fakeChannel.closeCode = 1005;
      fakeChannel.closeReason = 'No status';

      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        sessionId: 'getters-test',
      );

      expect(channel.closeCode, equals(1005));
      expect(channel.closeReason, equals('No status'));

      final doneFuture = channel.sink.done;
      await channel.sink.close();
      await expectLater(doneFuture, completes);
    });

    test('closes connection with 1006 when ready future rejects', () async {
      final fake = FakeWebSocketChannel(autoReady: false);
      final channel = InterceptlyWebSocketChannel(
        fake,
        uri: Uri.parse('wss://example.com/ready-fail'),
        sessionId: 'ws-ready-fail',
      );
      expect(channel, isNotNull);

      fake.completeReadyError(StateError('Handshake failure'));
      await pumpEventQueue();

      final entry = session.entries.firstWhere((e) => e.id == 'ws-ready-fail');
      expect(entry.statusCode, equals(1006));
      expect(entry.hasError, isTrue);
      expect(entry.errorMessage, contains('Handshake failure'));
    });

    test('closes connection with 1006 when stream emits error', () async {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        uri: Uri.parse('wss://example.com/stream-err'),
        sessionId: 'ws-stream-err',
      );

      Object? receivedError;
      final sub = channel.stream.listen(
        (_) {},
        onError: (Object err) {
          receivedError = err;
        },
      );

      fakeChannel.emitIncomingError(StateError('Unexpected connection reset'));
      await pumpEventQueue();

      expect(receivedError, isA<StateError>());
      final entry = session.entries.firstWhere((e) => e.id == 'ws-stream-err');
      expect(entry.statusCode, equals(1006));
      expect(entry.hasError, isTrue);
      expect(entry.errorMessage, contains('Unexpected connection reset'));
      await sub.cancel();
    });

    test('captures ByteData payload as binary frame', () async {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        sessionId: 'ws-bytedata',
      );

      final bd = ByteData(4)..setUint32(0, 0x12345678);
      channel.sink.add(bd);
      await pumpEventQueue();

      expect(fakeChannel.sentData.first, equals(bd));
      final frames = session.getRealtimeFrames('ws-bytedata');
      expect(frames.length, equals(1));
      expect(frames.first.type, equals(FrameType.binary));
      expect(frames.first.binaryPayload, isNotNull);
      expect(frames.first.payloadSizeBytes, equals(4));
    });

    test('truncates payload according to session maxBodyBytes', () async {
      session.configureSession(session.settings.copyWith(maxBodyBytes: 32));
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        sessionId: 'ws-truncate',
      );

      final bigText = 'A' * 100;
      channel.sink.add(bigText);
      await pumpEventQueue();

      final frames = session.getRealtimeFrames('ws-truncate');
      expect(frames.length, equals(1));
      expect(frames.first.textPayload!.length, equals(32));
    });
  });

  group('RealtimeCaptureAdapter and TrafficCollector Delegation', () {
    late FakeWebSocketChannel fakeChannel;
    late _SpyRealtimeTrafficCollector spyCollector;

    setUp(() async {
      await InspectorSession.resetForTesting();
      fakeChannel = FakeWebSocketChannel(protocol: 'spy-v1');
      spyCollector = _SpyRealtimeTrafficCollector();
    });

    tearDown(() async {
      await InspectorSession.resetForTesting();
    });

    test('exposes collector and scope getters', () {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        collector: spyCollector,
      );

      expect(channel.collector, equals(spyCollector));
      expect(channel.scope, isA<RealtimeSessionScope>());
      expect(channel.sessionId, equals(channel.scope.sessionId));
    });

    test('binds custom collector via constructor and factories', () {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        collector: spyCollector,
      );

      expect(channel.collector, equals(spyCollector));
    });

    test('delegates connection handshake to collector.recordConnection', () {
      final uri = Uri.parse('wss://example.com/handshake');
      InterceptlyWebSocketChannel(
        fakeChannel,
        uri: uri,
        sessionId: 'session-handshake',
        headers: {'X-Test': 'Value'},
        collector: spyCollector,
      );

      expect(spyCollector.recordConnectionCalls.length, equals(1));
      final call = spyCollector.recordConnectionCalls.first;
      expect(call['sessionId'], equals('session-handshake'));
      expect(call['uri'], equals(uri));
      expect(call['headers'], equals({'X-Test': 'Value'}));
    });

    test('records connection with fallback uri when uri is null', () {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        collector: spyCollector,
      );

      expect(channel.uri, equals(Uri(scheme: 'ws', host: 'unknown-socket')));
      expect(spyCollector.recordConnectionCalls.length, equals(1));
      final call = spyCollector.recordConnectionCalls.first;
      expect(call['uri'], equals(Uri(scheme: 'ws', host: 'unknown-socket')));
    });

    test(
        'delegates outgoing frames (text, binary, list) to collector.recordFrame',
        () async {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        sessionId: 'out-frames',
        collector: spyCollector,
      );

      channel.sink.add('text payload');
      channel.sink.add(Uint8List.fromList([1, 2, 3]));
      channel.sink.add(<int>[4, 5, 6]);
      await pumpEventQueue();

      expect(spyCollector.recordFrameCalls.length, equals(3));

      expect(
          spyCollector.recordFrameCalls[0]['sessionId'], equals('out-frames'));
      expect(spyCollector.recordFrameCalls[0]['direction'],
          equals(FrameDirection.outgoing));
      expect(spyCollector.recordFrameCalls[0]['type'], equals(FrameType.text));
      expect(
          spyCollector.recordFrameCalls[0]['payload'], equals('text payload'));

      expect(
          spyCollector.recordFrameCalls[1]['sessionId'], equals('out-frames'));
      expect(spyCollector.recordFrameCalls[1]['direction'],
          equals(FrameDirection.outgoing));
      expect(
          spyCollector.recordFrameCalls[1]['type'], equals(FrameType.binary));
      expect(spyCollector.recordFrameCalls[1]['payload'],
          equals(Uint8List.fromList([1, 2, 3])));

      expect(
          spyCollector.recordFrameCalls[2]['sessionId'], equals('out-frames'));
      expect(spyCollector.recordFrameCalls[2]['direction'],
          equals(FrameDirection.outgoing));
      expect(
          spyCollector.recordFrameCalls[2]['type'], equals(FrameType.binary));
      expect(
          spyCollector.recordFrameCalls[2]['payload'], equals(<int>[4, 5, 6]));
    });

    test('delegates incoming frames to collector.recordFrame', () async {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        sessionId: 'in-frames',
        collector: spyCollector,
      );

      final received = <dynamic>[];
      final sub = channel.stream.listen(received.add);
      addTearDown(sub.cancel);

      fakeChannel.emitIncoming('incoming text');
      fakeChannel.emitIncoming(Uint8List.fromList([7, 8, 9]));
      await pumpEventQueue();

      expect(received.length, equals(2));
      expect(spyCollector.recordFrameCalls.length, equals(2));

      expect(spyCollector.recordFrameCalls[0]['direction'],
          equals(FrameDirection.incoming));
      expect(spyCollector.recordFrameCalls[0]['type'], equals(FrameType.text));
      expect(
          spyCollector.recordFrameCalls[0]['payload'], equals('incoming text'));

      expect(spyCollector.recordFrameCalls[1]['direction'],
          equals(FrameDirection.incoming));
      expect(
          spyCollector.recordFrameCalls[1]['type'], equals(FrameType.binary));
      expect(spyCollector.recordFrameCalls[1]['payload'],
          equals(Uint8List.fromList([7, 8, 9])));
    });

    test('delegates sink.close and server close to collector.recordClose',
        () async {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        sessionId: 'close-delegation',
        collector: spyCollector,
      );

      await channel.sink.close(1000, 'Normal Client Close');
      await pumpEventQueue();

      expect(spyCollector.recordCloseCalls.length, equals(1));
      expect(spyCollector.recordCloseCalls[0]['sessionId'],
          equals('close-delegation'));
      expect(spyCollector.recordCloseCalls[0]['closeCode'], equals(1000));
      expect(spyCollector.recordCloseCalls[0]['closeReason'],
          equals('Normal Client Close'));
    });

    test(
        'resilient against collector exceptions without breaking socket traffic',
        () async {
      spyCollector.throwOnConnection = true;
      spyCollector.throwOnFrame = true;
      spyCollector.throwOnClose = true;

      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        uri: Uri.parse('wss://example.com/throwing'),
        sessionId: 'throwing-session',
        collector: spyCollector,
      );

      // Sending frames should not throw
      channel.sink.add('safe outgoing');
      await pumpEventQueue();
      expect(fakeChannel.sentData, equals(['safe outgoing']));

      // Receiving frames should not throw
      final received = <dynamic>[];
      final sub = channel.stream.listen(received.add);
      addTearDown(sub.cancel);

      fakeChannel.emitIncoming('safe incoming');
      await pumpEventQueue();
      expect(received, equals(['safe incoming']));

      // Closing should not throw
      await channel.sink.close(1000, 'Safe close');
      await pumpEventQueue();
      expect(fakeChannel.sinkClosed, isTrue);
    });

    test('sink.add forwards to underlying sink before recording', () async {
      spyCollector.throwOnFrame = true;
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        sessionId: 'ws-forward-first',
        collector: spyCollector,
      );

      channel.sink.add('must be sent despite collector throwing');
      await pumpEventQueue();

      expect(
        fakeChannel.sentData,
        equals(['must be sent despite collector throwing']),
      );
    });

    test('attaches RealtimeConnectionSender to scope and transmits messages', () async {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        sessionId: 'ws-sender-test',
        collector: spyCollector,
      );

      expect(channel.scope.canSend, isTrue);
      expect(
        channel.scope.sender?.protocolType,
        equals(RealtimeProtocolType.webSocket),
      );

      const draft = RealtimeMessageDraft(payload: 'Hello from Interceptly UI');
      await channel.scope.sendToServer(draft);
      await pumpEventQueue();

      expect(fakeChannel.sentData, contains('Hello from Interceptly UI'));
      expect(
        spyCollector.recordFrameCalls.any(
          (c) =>
              c['direction'] == FrameDirection.outgoing &&
              c['payload'] == 'Hello from Interceptly UI',
        ),
        isTrue,
      );

      await channel.sink.close(1000, 'Normal');
      await pumpEventQueue();

      expect(channel.scope.canSend, isFalse);
      expect(
        () => channel.scope.sendToServer(draft),
        throwsStateError,
      );
    });
  });
}

class _SpyRealtimeTrafficCollector implements RealtimeTrafficCollector {
  _SpyRealtimeTrafficCollector([InspectorSession? session])
      : session = session ?? InspectorSession.instance;

  final InspectorSession session;

  final List<Map<String, dynamic>> recordConnectionCalls = [];
  final List<Map<String, dynamic>> recordFrameCalls = [];
  final List<Map<String, dynamic>> recordCloseCalls = [];
  final Map<String, RealtimeSessionScope> _activeScopes = {};

  bool throwOnConnection = false;
  bool throwOnFrame = false;
  bool throwOnClose = false;

  @override
  int get maxBodyBytes => session.settings.maxBodyBytes;

  @override
  int get offloadThreshold => session.settings.realtimeBodyOffloadThreshold;

  @override
  bool shouldCapture(Uri? uri) => true;

  @override
  RealtimeSessionScope openSession({
    Uri? uri,
    String? sessionId,
    Map<String, String>? headers,
    RealtimeProtocolType protocolType = RealtimeProtocolType.webSocket,
  }) {
    final effectiveId = sessionId ?? RequestId.generate();

    if (uri != null) {
      try {
        recordConnection(
          sessionId: effectiveId,
          uri: uri,
          headers: headers,
        );
      } catch (_) {}
    }

    final scope = RealtimeSessionScope(
      collector: this,
      sessionId: effectiveId,
      uri: uri,
      protocolType: protocolType,
    );
    _activeScopes[effectiveId] = scope;
    return scope;
  }

  @override
  bool canSend(String sessionId) => _activeScopes[sessionId]?.canSend ?? false;

  @override
  RealtimeConnectionSender? getSender(String sessionId) =>
      _activeScopes[sessionId]?.sender;

  @override
  Future<void> sendMessage(String sessionId, RealtimeMessageDraft draft) async {
    final scope = _activeScopes[sessionId];
    if (scope == null) throw StateError('No scope found for session $sessionId');
    await scope.sendToServer(draft);
  }

  @override
  void recordConnection({
    required String sessionId,
    required Uri uri,
    Map<String, String>? headers,
    RealtimeProtocolType protocolType = RealtimeProtocolType.webSocket,
  }) {
    if (throwOnConnection) throw Exception('Simulated recordConnection error');
    recordConnectionCalls.add({
      'sessionId': sessionId,
      'uri': uri,
      'headers': headers,
      'protocolType': protocolType,
    });
  }

  @override
  void recordFrame({
    required String sessionId,
    required FrameDirection direction,
    required FrameType type,
    required dynamic payload,
    int? payloadSizeBytes,
    DateTime? timestamp,
    String? shortPreview,
    bool? shouldOffload,
    String? eventName,
  }) {
    if (throwOnFrame) throw Exception('Simulated recordFrame error');
    recordFrameCalls.add({
      'sessionId': sessionId,
      'direction': direction,
      'type': type,
      'payload': payload,
      'payloadSizeBytes': payloadSizeBytes,
      'timestamp': timestamp,
      'shortPreview': shortPreview,
      'shouldOffload': shouldOffload,
      'eventName': eventName,
    });
  }

  @override
  void recordClose({
    required String sessionId,
    int? closeCode,
    String? closeReason,
  }) {
    if (throwOnClose) throw Exception('Simulated recordClose error');
    recordCloseCalls.add({
      'sessionId': sessionId,
      'closeCode': closeCode,
      'closeReason': closeReason,
    });
  }
}
