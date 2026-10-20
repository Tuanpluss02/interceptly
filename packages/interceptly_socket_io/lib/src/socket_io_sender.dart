import 'dart:async';
import 'dart:convert';

import 'package:interceptly/adapter.dart';
import 'package:socket_io_client/socket_io_client.dart';

/// A [RealtimeConnectionSender] delegate that transmits messages over a Socket.IO connection.
class SocketIoSender implements RealtimeConnectionSender {
  /// The underlying Socket.IO client.
  final Socket socket;

  final RealtimeSessionScope Function() _scopeGetter;

  /// The realtime session scope tracking this connection exchange.
  RealtimeSessionScope get scope => _scopeGetter();

  /// Creates a [SocketIoSender] binding [socket] and [scope].
  SocketIoSender(this.socket, RealtimeSessionScope scope)
      : _scopeGetter = (() => scope);

  /// Creates a [SocketIoSender] binding [socket] and a dynamic scope getter function
  /// that tracks session re-openings across reconnections.
  SocketIoSender.dynamic(this.socket, this._scopeGetter);

  @override
  RealtimeProtocolType get protocolType => RealtimeProtocolType.socketIo;

  @override
  bool get canSend => socket.connected && !scope.isClosed;

  @override
  Future<void> send(RealtimeMessageDraft draft) async {
    if (!canSend) {
      throw StateError(
        'Cannot send message: Socket.IO connection is disconnected or session closed',
      );
    }

    final event = (draft.event != null && draft.event!.isNotEmpty)
        ? draft.event!
        : 'message';

    dynamic payload = draft.payload;
    if (payload is String && payload.isNotEmpty) {
      final trimmed = payload.trim();
      if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
          (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
        try {
          payload = jsonDecode(trimmed);
        } catch (_) {
          // If not valid JSON, leave as original string.
        }
      }
    }

    socket.emit(event, payload);
  }
}
