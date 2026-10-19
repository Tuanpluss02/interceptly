import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly_web_socket/interceptly_web_socket.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  final _controller = StreamController<dynamic>();
  final _sinkController = StreamController<dynamic>();

  @override
  Stream get stream => _controller.stream;

  @override
  late final WebSocketSink sink = _FakeWebSocketSink(_sinkController);

  @override
  Future<void> get ready => Future.value();

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

class _FakeWebSocketSink implements WebSocketSink {
  final StreamController<dynamic> _controller;
  _FakeWebSocketSink(this._controller);

  @override
  void add(dynamic data) => _controller.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _controller.addError(error, stackTrace);

  @override
  Future addStream(Stream stream) => _controller.addStream(stream);

  @override
  Future close([int? closeCode, String? closeReason]) => _controller.close();

  @override
  Future get done => _controller.done;
}

void main() {
  group('Interceptly WebSocket Smoke Test', () {
    test('instantiates InterceptlyWebSocketChannel', () {
      final fakeChannel = _FakeWebSocketChannel();
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        uri: Uri.parse('wss://echo.websocket.events'),
      );
      expect(channel, isNotNull);
      expect(channel.sessionId, isNotEmpty);
      expect(channel.uri, equals(Uri.parse('wss://echo.websocket.events')));
    });
  });
}
