import 'dart:async';
import 'dart:typed_data';

import 'package:interceptly/interceptly.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A wrapper around [WebSocketChannel] that captures incoming and outgoing
/// frames and connection lifecycle events for the Interceptly inspector.
class InterceptlyWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel, RealtimeCaptureAdapter {
  final WebSocketChannel _inner;

  /// The unique session ID for this WebSocket connection.
  final String sessionId;

  /// The target URI for this connection, if provided.
  final Uri? uri;

  /// The initial handshake headers for this connection, if provided.
  final Map<String, String>? headers;

  @override
  InspectorSession get session => InspectorSession.instance;

  @override
  final RealtimeTrafficCollector collector;

  bool _isClosed = false;

  /// Creates an [InterceptlyWebSocketChannel] wrapping [inner].
  ///
  /// If [sessionId] is omitted, a unique ID is generated automatically.
  /// If [uri] is provided, an initial realtime connection is recorded with
  /// [collector].
  InterceptlyWebSocketChannel(
    WebSocketChannel inner, {
    this.uri,
    String? sessionId,
    RealtimeTrafficCollector? collector,
    this.headers,
  })  : _inner = inner,
        sessionId = sessionId ?? RequestId.generate(),
        collector = collector ?? DefaultRealtimeTrafficCollector() {
    if (uri != null) {
      try {
        this.collector.recordConnection(
          sessionId: this.sessionId,
          uri: uri!,
          headers: headers,
        );
      } catch (_) {
        /// Prevent inspector failures from interrupting application traffic.
      }
    }
    unawaited(
      _inner.ready.then(
        (_) => null,
        onError: (Object error, StackTrace? _) {
          _closeConnection(1006, error.toString());
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

  /// The [Interceptly] facade instance.
  Interceptly get interceptly => Interceptly.instance;

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
        _closeConnection(1006, error.toString());
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
      final dynamic payload;
      final FrameType type;
      if (data is Uint8List) {
        type = FrameType.binary;
        payload = _truncateBinary(data);
      } else if (data is ByteData) {
        type = FrameType.binary;
        payload = _truncateBinary(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } else if (data is List<int>) {
        type = FrameType.binary;
        payload = _truncateBinary(Uint8List.fromList(data));
      } else if (data is String) {
        type = FrameType.text;
        payload = _truncateText(data);
      } else {
        type = FrameType.text;
        payload = data != null ? _truncateText(data.toString()) : null;
      }
      collector.recordFrame(
        sessionId: sessionId,
        direction: direction,
        type: type,
        payload: payload,
      );
    } catch (_) {
      /// Prevent inspector failures from interrupting application traffic.
    }
  }

  Uint8List _truncateBinary(Uint8List bytes) {
    final maxBytes = session.settings.maxBodyBytes;
    if (maxBytes <= 0 || bytes.length <= maxBytes) return bytes;
    return Uint8List.sublistView(bytes, 0, maxBytes);
  }

  String _truncateText(String text) {
    final maxBytes = session.settings.maxBodyBytes;
    if (maxBytes <= 0 || text.length <= maxBytes) return text;
    return text.substring(0, maxBytes);
  }

  void _closeConnection([int? closeCode, String? closeReason]) {
    if (_isClosed) return;
    _isClosed = true;
    try {
      collector.recordClose(
        sessionId: sessionId,
        closeCode: closeCode ?? _inner.closeCode ?? 1000,
        closeReason: closeReason ?? _inner.closeReason,
      );
    } catch (_) {
      /// Prevent inspector failures from interrupting application traffic.
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
    _innerSink.add(data);
    _channel._recordFrame(data, FrameDirection.outgoing);
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
