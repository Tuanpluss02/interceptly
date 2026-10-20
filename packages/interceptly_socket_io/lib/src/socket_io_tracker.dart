import 'package:interceptly/adapter.dart';
import 'package:socket_io_client/socket_io_client.dart';

import 'socket_io_sender.dart';

const Object _omitted = Object();

typedef _AnyEventHandler = dynamic Function(
  String event, [
  dynamic a1,
  dynamic a2,
  dynamic a3,
  dynamic a4,
  dynamic a5,
  dynamic a6,
  dynamic a7,
  dynamic a8,
  dynamic a9,
  dynamic a10,
  dynamic a11,
  dynamic a12,
  dynamic a13,
  dynamic a14,
  dynamic a15,
  dynamic a16,
  dynamic a17,
  dynamic a18,
  dynamic a19,
  dynamic a20,
]);

/// Tracks an active [Socket] connection, listening for incoming and outgoing events
/// and connection lifecycle changes for the Interceptly inspector.
class InterceptlySocketIoTracker {
  /// The underlying Socket.IO client being tracked.
  final Socket socket;

  /// Target URI of the connection.
  final Uri uri;

  /// The initial handshake headers for this connection, if provided.
  final Map<String, String>? headers;

  /// The [RealtimeTrafficCollector] coordinating capture.
  final RealtimeTrafficCollector collector;

  RealtimeSessionScope _scope;

  /// The active [RealtimeSessionScope] recording traffic.
  RealtimeSessionScope get scope => _scope;

  late final _AnyEventHandler _incomingHandler;
  late final _AnyEventHandler _outgoingHandler;
  late final void Function(dynamic) _connectHandler;
  late final void Function(dynamic) _disconnectHandler;
  late final void Function(dynamic) _connectErrorHandler;

  bool _isDetached = false;

  /// Whether this tracker has been detached from [socket].
  bool get isDetached => _isDetached;

  /// Creates a tracker for [socket], attaching event and lifecycle listeners.
  InterceptlySocketIoTracker({
    required this.socket,
    required RealtimeSessionScope scope,
    required this.collector,
    required this.uri,
    this.headers,
  }) : _scope = scope {
    _incomingHandler = _handleIncoming;
    _outgoingHandler = _handleOutgoing;
    _connectHandler = _handleConnect;
    _disconnectHandler = _handleDisconnect;
    _connectErrorHandler = _handleConnectError;

    _attachListeners();
  }

  void _attachListeners() {
    guardCapture(() {
      socket.onAny(_incomingHandler);
      socket.onAnyOutgoing(_outgoingHandler);
      socket.on('connect', _connectHandler);
      socket.on('disconnect', _disconnectHandler);
      socket.on('connect_error', _connectErrorHandler);
    });
  }

  /// Detaches all event listeners from the underlying [socket], unregisters
  /// the sender, and closes the active session scope.
  ///
  /// This operation is idempotent and safe to call multiple times.
  void detach() {
    if (_isDetached) return;
    _isDetached = true;

    guardCapture(() {
      socket.offAny(_incomingHandler);
      socket.offAnyOutgoing(_outgoingHandler);
      socket.off('connect', _connectHandler);
      socket.off('disconnect', _disconnectHandler);
      socket.off('connect_error', _connectErrorHandler);
      _scope.detachSender();
      if (!_scope.isClosed) {
        _scope.close(code: 1000, reason: 'Tracker detached');
      }
    });
  }

  dynamic _handleIncoming(
    String event, [
    dynamic a1 = _omitted,
    dynamic a2 = _omitted,
    dynamic a3 = _omitted,
    dynamic a4 = _omitted,
    dynamic a5 = _omitted,
    dynamic a6 = _omitted,
    dynamic a7 = _omitted,
    dynamic a8 = _omitted,
    dynamic a9 = _omitted,
    dynamic a10 = _omitted,
    dynamic a11 = _omitted,
    dynamic a12 = _omitted,
    dynamic a13 = _omitted,
    dynamic a14 = _omitted,
    dynamic a15 = _omitted,
    dynamic a16 = _omitted,
    dynamic a17 = _omitted,
    dynamic a18 = _omitted,
    dynamic a19 = _omitted,
    dynamic a20 = _omitted,
  ]) {
    if (_isDetached) return;
    guardCapture(() {
      final payload = _resolvePayload([
        a1,
        a2,
        a3,
        a4,
        a5,
        a6,
        a7,
        a8,
        a9,
        a10,
        a11,
        a12,
        a13,
        a14,
        a15,
        a16,
        a17,
        a18,
        a19,
        a20,
      ]);
      _scope.receive(payload ?? '', eventName: event);
    });
  }

  dynamic _handleOutgoing(
    String event, [
    dynamic a1 = _omitted,
    dynamic a2 = _omitted,
    dynamic a3 = _omitted,
    dynamic a4 = _omitted,
    dynamic a5 = _omitted,
    dynamic a6 = _omitted,
    dynamic a7 = _omitted,
    dynamic a8 = _omitted,
    dynamic a9 = _omitted,
    dynamic a10 = _omitted,
    dynamic a11 = _omitted,
    dynamic a12 = _omitted,
    dynamic a13 = _omitted,
    dynamic a14 = _omitted,
    dynamic a15 = _omitted,
    dynamic a16 = _omitted,
    dynamic a17 = _omitted,
    dynamic a18 = _omitted,
    dynamic a19 = _omitted,
    dynamic a20 = _omitted,
  ]) {
    if (_isDetached) return;
    guardCapture(() {
      final payload = _resolvePayload([
        a1,
        a2,
        a3,
        a4,
        a5,
        a6,
        a7,
        a8,
        a9,
        a10,
        a11,
        a12,
        a13,
        a14,
        a15,
        a16,
        a17,
        a18,
        a19,
        a20,
      ]);
      _scope.send(payload ?? '', eventName: event);
    });
  }

  void _handleConnect([dynamic _]) {
    if (_isDetached) return;
    guardCapture(() {
      if (_scope.isClosed) {
        // Reconnection occurred: open a fresh session scope for this connection
        _scope = collector.openSession(
          uri: uri,
          protocolType: RealtimeProtocolType.socketIo,
          headers: headers,
        );
        _scope.attachSender(SocketIoSender.dynamic(socket, () => _scope));
      }
    });
  }

  void _handleDisconnect([dynamic reason]) {
    if (_isDetached) return;
    guardCapture(() {
      if (!_scope.isClosed) {
        _scope.close(code: 1000, reason: reason?.toString());
      }
    });
  }

  void _handleConnectError([dynamic error]) {
    if (_isDetached) return;
    guardCapture(() {
      if (!_scope.isClosed) {
        _scope.close(code: 1006, reason: error?.toString());
      }
    });
  }

  static dynamic _resolvePayload(List<dynamic> candidates) {
    final passed = <dynamic>[];
    for (final item in candidates) {
      if (identical(item, _omitted)) break;
      passed.add(item);
    }

    if (passed.isEmpty) return '';
    if (passed.length == 1) return passed.first;
    return passed;
  }
}
