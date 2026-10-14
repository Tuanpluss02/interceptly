import 'dart:async';

import 'package:interceptly/adapter.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A wrapper around [WebSocketChannel] that captures incoming and outgoing
/// frames and connection lifecycle events for the Interceptly inspector.
class InterceptlyWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  final WebSocketChannel _inner;

  /// The traffic collector coordinating capture.
  final RealtimeTrafficCollector collector;

  /// The realtime session scope tracking this connection exchange.
  final RealtimeSessionScope scope;

  /// The initial handshake headers for this connection, if provided.
  final Map<String, String>? headers;

  /// The unique session ID for this WebSocket connection.
  String get sessionId => scope.sessionId;

  /// The target URI for this connection, if provided.
  Uri? get uri => scope.uri;

  /// Creates an [InterceptlyWebSocketChannel] wrapping [inner].
  InterceptlyWebSocketChannel(
    WebSocketChannel inner, {
    Uri? uri,
    String? sessionId,
    RealtimeTrafficCollector? collector,
    this.headers,
  })  : _inner = inner,
        collector = collector ?? RealtimeTrafficCollector.instance,
        scope = (collector ?? RealtimeTrafficCollector.instance).openSession(
          uri: uri,
          sessionId: sessionId,
          headers: headers,
        ) {
    unawaited(
      _inner.ready.then(
        (_) => null,
        onError: (Object error, StackTrace? _) {
          scope.close(code: 1006, reason: error.toString());
        },
      ),
    );
  }

  /// Convenience wrapper around an existing [WebSocketChannel].
  static InterceptlyWebSocketChannel wrap(
    WebSocketChannel inner, {
    Uri? uri,
    String? sessionId,
    RealtimeTrafficCollector? collector,
    Map<String, String>? headers,
  }) {
    return InterceptlyWebSocketChannel(
      inner,
      uri: uri,
      sessionId: sessionId,
      collector: collector,
      headers: headers,
    );
  }

  /// Connects to [uri] and wraps the resulting channel with Interceptly capture.
  static InterceptlyWebSocketChannel connect(
    Uri uri, {
    Iterable<String>? protocols,
    String? sessionId,
    RealtimeTrafficCollector? collector,
    Map<String, String>? headers,
  }) {
    final inner = WebSocketChannel.connect(uri, protocols: protocols);
    return InterceptlyWebSocketChannel(
      inner,
      uri: uri,
      sessionId: sessionId,
      collector: collector,
      headers: headers,
    );
  }

  /// The underlying [WebSocketChannel] instance.
  WebSocketChannel get inner => _inner;

  @override
  String? get protocol => _inner.protocol;

  @override
  int? get closeCode => _inner.closeCode;

  @override
  String? get closeReason => _inner.closeReason;

  @override
  Future<void> get ready => _inner.ready;

  @override
  Stream get stream => _stream;

  @override
  late final WebSocketSink sink = _InterceptlyWebSocketSink(this, _inner.sink);

  late final Stream _stream = _inner.stream.transform(
    StreamTransformer<dynamic, dynamic>.fromHandlers(
      handleData: (dynamic data, EventSink<dynamic> sink) {
        scope.receive(data);
        sink.add(data);
      },
      handleError:
          (Object error, StackTrace stackTrace, EventSink<dynamic> sink) {
        scope.close(code: 1006, reason: error.toString());
        sink.addError(error, stackTrace);
      },
      handleDone: (EventSink<dynamic> sink) {
        scope.close(code: _inner.closeCode, reason: _inner.closeReason);
        sink.close();
      },
    ),
  );
}

/// A [WebSocketSink] wrapper that intercepts outgoing frames and close events.
class _InterceptlyWebSocketSink implements WebSocketSink {
  final InterceptlyWebSocketChannel _channel;
  final WebSocketSink _innerSink;

  _InterceptlyWebSocketSink(this._channel, this._innerSink);

  @override
  void add(dynamic data) {
    _innerSink.add(data);
    _channel.scope.send(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _innerSink.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<dynamic> stream) {
    final intercepted = stream.map((dynamic item) {
      _channel.scope.send(item);
      return item;
    });
    return _innerSink.addStream(intercepted);
  }

  @override
  Future<dynamic> close([int? closeCode, String? closeReason]) {
    _channel.scope.close(code: closeCode, reason: closeReason);
    return _innerSink.close(closeCode, closeReason);
  }

  @override
  Future<dynamic> get done => _innerSink.done;
}
