// ignore_for_file: implementation_imports

import 'dart:typed_data';

import 'package:socket_io_client/socket_io_client.dart';
import 'package:socket_io_client/src/manager.dart';

/// A controllable [Socket] test double for unit testing Interceptly's Socket.IO adapter.
class FakeSocket extends Socket {
  /// Captured packets passed to [packet].
  final List<Map<dynamic, dynamic>> sentPackets = [];

  /// Creates a [FakeSocket] without establishing network connections.
  FakeSocket({
    String uri = 'http://localhost:3000',
    String nsp = '/',
    Map<dynamic, dynamic>? opts,
  }) : super(
          Manager(
            uri: uri,
            options: <dynamic, dynamic>{'autoConnect': false, ...?opts},
          ),
          nsp,
          <dynamic, dynamic>{'autoConnect': false, ...?opts},
        ) {
    connected = true;
  }

  @override
  void packet(Map packet) {
    sentPackets.add(packet);
  }

  /// Triggers an incoming event from the server using `emitEvent`.
  void triggerIncomingEvent(String eventName, [dynamic payload]) {
    if (payload != null) {
      if (payload is List && payload is! Uint8List) {
        emitEvent([eventName, ...payload]);
      } else {
        emitEvent([eventName, payload]);
      }
    } else {
      emitEvent([eventName]);
    }
  }

  /// Triggers an incoming event with variadic arguments directly to listeners.
  void triggerIncomingVariadic(String eventName, List<dynamic> args) {
    final fullArgs = [eventName, ...args];
    final listeners = List.from(listenersAny());
    for (final listener in listeners) {
      Function.apply(listener, fullArgs);
    }
  }

  /// Simulates an outgoing event emission with variadic arguments.
  void emitVariadic(String eventName, List<dynamic> args) {
    final fullArgs = [eventName, ...args];
    final listeners = List.from(listenersAnyOutgoing());
    for (final listener in listeners) {
      Function.apply(listener, fullArgs);
    }
  }

  /// Simulates server connect.
  void triggerConnect([String sid = 'fake-socket-id']) {
    onconnect(sid, null);
  }

  /// Simulates server disconnect.
  void triggerDisconnect([String reason = 'io server disconnect']) {
    emitReserved('disconnect', reason);
    connected = false;
  }

  /// Simulates server connection error.
  void triggerConnectError([dynamic error = 'connection failed']) {
    emitReserved('connect_error', error);
  }
}

/// A fake socket that throws when accessing `io` after construction to test error fallback.
class FallbackFakeSocket extends FakeSocket {
  bool _throwOnIoAccess = false;

  FallbackFakeSocket({super.nsp}) {
    _throwOnIoAccess = true;
  }

  @override
  Manager get io {
    if (_throwOnIoAccess) {
      throw StateError('Manager io unavailable');
    }
    return super.io;
  }
}
