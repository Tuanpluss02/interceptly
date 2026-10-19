import 'package:interceptly/adapter.dart';
import 'package:socket_io_client/socket_io_client.dart';

/// Tracks an active [Socket] connection, listening for incoming and outgoing events
/// and connection lifecycle changes for the Interceptly inspector.
class InterceptlySocketIoTracker {
  /// The underlying Socket.IO client being tracked.
  final Socket socket;

  /// The active [RealtimeSessionScope] recording traffic.
  final RealtimeSessionScope scope;

  /// The [RealtimeTrafficCollector] coordinating capture.
  final RealtimeTrafficCollector collector;

  late final dynamic _incomingHandler;
  late final dynamic _outgoingHandler;
  late final dynamic _connectHandler;
  late final dynamic _disconnectHandler;
  late final dynamic _connectErrorHandler;

  bool _isDetached = false;

  /// Whether this tracker has been detached from [socket].
  bool get isDetached => _isDetached;

  /// Creates a tracker for [socket], attaching event and lifecycle listeners.
  InterceptlySocketIoTracker({
    required this.socket,
    required this.scope,
    required this.collector,
  }) {
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

  /// Detaches all event listeners from the underlying [socket] and unregisters
  /// the sender from [scope].
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
      scope.detachSender();
    });
  }

  dynamic _handleIncoming(
    dynamic event, [
    dynamic a1,
    dynamic a2,
    dynamic a3,
    dynamic a4,
    dynamic a5,
    dynamic a6,
    dynamic a7,
    dynamic a8,
    dynamic a9,
  ]) {
    if (_isDetached) return;
    guardCapture(() {
      final eventName = event?.toString();
      final payload = _resolvePayload(a1, a2, a3, a4, a5, a6, a7, a8, a9);
      scope.receive(payload ?? '', eventName: eventName);
    });
  }

  dynamic _handleOutgoing(
    dynamic event, [
    dynamic a1,
    dynamic a2,
    dynamic a3,
    dynamic a4,
    dynamic a5,
    dynamic a6,
    dynamic a7,
    dynamic a8,
    dynamic a9,
  ]) {
    if (_isDetached) return;
    guardCapture(() {
      final eventName = event?.toString();
      final payload = _resolvePayload(a1, a2, a3, a4, a5, a6, a7, a8, a9);
      scope.send(payload ?? '', eventName: eventName);
    });
  }

  dynamic _handleConnect([dynamic _]) {
    // Session is active; sender dynamically reflects socket.connected.
  }

  dynamic _handleDisconnect([dynamic reason]) {
    if (_isDetached) return;
    guardCapture(() {
      scope.close(code: 1000, reason: reason?.toString());
    });
  }

  dynamic _handleConnectError([dynamic error]) {
    if (_isDetached) return;
    guardCapture(() {
      scope.close(code: 1006, reason: error?.toString());
    });
  }

  static dynamic _resolvePayload(
    dynamic a1, [
    dynamic a2,
    dynamic a3,
    dynamic a4,
    dynamic a5,
    dynamic a6,
    dynamic a7,
    dynamic a8,
    dynamic a9,
  ]) {
    if (a2 == null &&
        a3 == null &&
        a4 == null &&
        a5 == null &&
        a6 == null &&
        a7 == null &&
        a8 == null &&
        a9 == null) {
      return a1;
    }
    final rawList = [a1, a2, a3, a4, a5, a6, a7, a8, a9];
    int lastNonNull = rawList.length - 1;
    while (lastNonNull >= 0 && rawList[lastNonNull] == null) {
      lastNonNull--;
    }
    if (lastNonNull < 0) return null;
    return rawList.sublist(0, lastNonNull + 1);
  }
}
