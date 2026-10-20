import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_web_socket/interceptly_web_socket.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  final _controller = StreamController<dynamic>();

  @override
  Stream get stream => _controller.stream;

  @override
  late final WebSocketSink sink = _FakeWebSocketSink();

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
  final Completer<void> _doneCompleter = Completer<void>();

  @override
  void add(dynamic data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) => Future.value();

  @override
  Future close([int? closeCode, String? closeReason]) {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    return Future.value();
  }

  @override
  Future get done => _doneCompleter.future;
}

void main() {
  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('Interceptly WebSocket Smoke Test', () {
    test('instantiates InterceptlyWebSocketChannel', () async {
      final fakeChannel = _FakeWebSocketChannel();
      final channel = InterceptlyWebSocketChannel(
        fakeChannel,
        uri: Uri.parse('wss://echo.websocket.events'),
      );
      expect(channel, isNotNull);
      expect(channel.sessionId, isNotEmpty);
      expect(channel.uri, equals(Uri.parse('wss://echo.websocket.events')));
      await channel.sink.close();
    });
  });
}
