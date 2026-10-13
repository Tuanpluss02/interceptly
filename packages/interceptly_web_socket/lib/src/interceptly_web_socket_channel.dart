import 'dart:async';
import 'dart:typed_data';

import 'package:interceptly/interceptly.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A wrapper around [WebSocketChannel] that captures incoming and outgoing
/// frames and connection lifecycle events for the Interceptly inspector.
class InterceptlyWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  final WebSocketChannel _inner;
  final Interceptly _client;

  /// The unique session ID for this WebSocket connection.
  final String sessionId;

  /// The target URI for this connection, if provided.
  final Uri? uri;

  /// The initial handshake headers for this connection, if provided.
  final Map<String, String>? headers;

  bool _isClosed = false;

  /// Creates an [InterceptlyWebSocketChannel] wrapping [inner].
  ///
  /// If [sessionId] is omitted, a unique ID is generated automatically.
  /// If [uri] is provided, an initial realtime connection is recorded with
  /// [interceptly] (or [Interceptly.instance] if omitted).
  InterceptlyWebSocketChannel(
    WebSocketChannel inner, {
    this.uri,
    String? sessionId,
    Interceptly? interceptly,
    this.headers,
  })  : _inner = inner,
        _client = interceptly ?? Interceptly.instance,
        sessionId = sessionId ?? RequestId.generate() {
    if (uri != null) {
      try {
        _client.recordRealtimeConnection(
          id: this.sessionId,
          url: uri.toString(),
          headers: headers ?? const {},
        );
      } catch (_) {
        // Prevent inspector failures from interrupting application traffic.
      }
    }
  }

  /// Convenience wrapper around an existing [WebSocketChannel].
  static InterceptlyWebSocketChannel wrap(
    WebSocketChannel inner, {
    Uri? uri,
    String? sessionId,
    Interceptly? interceptly,
    Map<String, String>? headers,
  }) {
    return InterceptlyWebSocketChannel(
      inner,
      uri: uri,
      sessionId: sessionId,
      interceptly: interceptly,
      headers: headers,
    );
  }

  /// Connects to [uri] and wraps the resulting channel with Interceptly capture.
  static InterceptlyWebSocketChannel connect(
    Uri uri, {
    Iterable<String>? protocols,
    String? sessionId,
    Interceptly? interceptly,
    Map<String, String>? headers,
  }) {
    final inner = WebSocketChannel.connect(uri, protocols: protocols);
    return InterceptlyWebSocketChannel(
      inner,
      uri: uri,
      sessionId: sessionId,
      interceptly: interceptly,
      headers: headers,
    );
  }

  /// The underlying [WebSocketChannel] instance.
  WebSocketChannel get inner => _inner;

  /// The [Interceptly] instance used for recording frames.
  Interceptly get interceptly => _client;

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
        _recordFrame(data, FrameDirection.incoming);
        sink.add(data);
      },
      handleError:
          (Object error, StackTrace stackTrace, EventSink<dynamic> sink) {
        sink.addError(error, stackTrace);
      },
      handleDone: (EventSink<dynamic> sink) {
        _closeConnection();
        sink.close();
      },
    ),
  );

  void _recordFrame(dynamic data, FrameDirection direction) {
    try {
      if (data is String) {
        _client.recordRealtimeFrame(
          RealtimeFrame.text(
            id: RequestId.generate(),
            sessionId: sessionId,
            direction: direction,
            text: data,
          ),
        );
      } else if (data is Uint8List) {
        _client.recordRealtimeFrame(
          RealtimeFrame.binary(
            id: RequestId.generate(),
            sessionId: sessionId,
            direction: direction,
            bytes: data,
          ),
        );
      } else if (data is List<int>) {
        _client.recordRealtimeFrame(
          RealtimeFrame.binary(
            id: RequestId.generate(),
            sessionId: sessionId,
            direction: direction,
            bytes: Uint8List.fromList(data),
          ),
        );
      }
    } catch (_) {
      // Prevent inspector failures from interrupting application traffic.
    }
  }

  void _closeConnection([int? closeCode, String? closeReason]) {
    if (_isClosed) return;
    _isClosed = true;
    try {
      _client.closeRealtimeConnection(
        sessionId,
        closeCode: closeCode ?? _inner.closeCode ?? 1000,
        closeReason: closeReason ?? _inner.closeReason,
      );
    } catch (_) {
      // Prevent inspector failures from interrupting application traffic.
    }
  }
}

/// A [WebSocketSink] wrapper that intercepts outgoing frames and close events.
class _InterceptlyWebSocketSink implements WebSocketSink {
  final InterceptlyWebSocketChannel _channel;
  final WebSocketSink _innerSink;

  _InterceptlyWebSocketSink(this._channel, this._innerSink);

  @override
  void add(dynamic data) {
    _channel._recordFrame(data, FrameDirection.outgoing);
    _innerSink.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _innerSink.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<dynamic> stream) {
    final intercepted = stream.map((dynamic item) {
      _channel._recordFrame(item, FrameDirection.outgoing);
      return item;
    });
    return _innerSink.addStream(intercepted);
  }

  @override
  Future<dynamic> close([int? closeCode, String? closeReason]) {
    _channel._closeConnection(closeCode, closeReason);
    return _innerSink.close(closeCode, closeReason);
  }

  @override
  Future<dynamic> get done => _innerSink.done;
}
