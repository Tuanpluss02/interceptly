import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
  })  : _streamController = streamController ?? StreamController<dynamic>(),
        _sinkController = sinkController ?? StreamController<dynamic>() {
    _readyCompleter.complete();
    _sinkController.stream.listen(
      sentData.add,
      onError: sinkErrors.add,
    );
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
    late Interceptly interceptly;
    late FakeWebSocketChannel fakeChannel;

    setUp(() {
      session = InspectorSession();
      interceptly = Interceptly(session: session);
      fakeChannel = FakeWebSocketChannel(protocol: 'chat-v1');
    });

    tearDown(() {
      session.dispose();
      interceptly.dispose();
    });

    test('initializes with custom sessionId, uri, headers and getters', () async {
      final uri = Uri.parse('wss://example.com/socket');
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        uri: uri,
        sessionId: 'custom-session-1',
        interceptly: interceptly,
        headers: {'Authorization': 'Bearer test'},
      );

      expect(channel.sessionId, equals('custom-session-1'));
      expect(channel.uri, equals(uri));
      expect(channel.headers, equals({'Authorization': 'Bearer test'}));
      expect(channel.protocol, equals('chat-v1'));
      expect(channel.inner, equals(fakeChannel));
      expect(channel.interceptly, equals(interceptly));
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

    test('auto-generates sessionId when omitted and skips uri if null', () {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        interceptly: interceptly,
      );

      expect(channel.sessionId, isNotEmpty);
      expect(channel.uri, isNull);
      expect(session.entries, isEmpty);
    });

    test('captures outgoing text frame via sink.add', () async {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        sessionId: 'ws-out-text',
        interceptly: interceptly,
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
        interceptly: interceptly,
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
        interceptly: interceptly,
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
        interceptly: interceptly,
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
        interceptly: interceptly,
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
        interceptly: interceptly,
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

    test('records closeRealtimeConnection on server stream completion', () async {
      final uri = Uri.parse('wss://example.com/server-close-test');
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        uri: uri,
        sessionId: 'ws-close-server',
        interceptly: interceptly,
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
        interceptly: interceptly,
      );

      final completer = Completer<void>();
      channel.stream.listen((_) {}, onDone: completer.complete);

      // Close client sink first
      await channel.sink.close(1000, 'Client closed');

      // Then server closes
      await fakeChannel.closeServer(code: 1006, reason: 'Abnormal');
      await completer.future;
      await pumpEventQueue();

      final entry =
          session.entries.firstWhere((e) => e.id == 'ws-idempotent');
      // Should retain client close status
      expect(entry.statusCode, equals(1000));
      expect(entry.errorMessage, equals('Client closed'));
    });

    test('propagates stream errors to subscriber', () async {
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        sessionId: 'ws-err',
        interceptly: interceptly,
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
        interceptly: interceptly,
      );

      channel.sink.addError(const FormatException('Bad data'));
      await pumpEventQueue();

      expect(fakeChannel.sinkErrors.length, equals(1));
      expect(fakeChannel.sinkErrors.first, isA<FormatException>());
    });

    test('wrap factory creates functional InterceptlyWebSocketChannel', () async {
      final uri = Uri.parse('wss://example.com/wrapped');
      final channel = InterceptlyWebSocketChannel.wrap(
        fakeChannel,
        uri: uri,
        sessionId: 'wrapped-id',
        interceptly: interceptly,
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
        interceptly: interceptly,
      );

      expect(channel.closeCode, equals(1005));
      expect(channel.closeReason, equals('No status'));

      final doneFuture = channel.sink.done;
      await channel.sink.close();
      await expectLater(doneFuture, completes);
    });
  });
}
