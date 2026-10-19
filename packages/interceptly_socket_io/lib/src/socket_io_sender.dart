import 'dart:async';

import 'package:interceptly/adapter.dart';
import 'package:socket_io_client/socket_io_client.dart';

/// A [RealtimeConnectionSender] delegate that transmits messages over a Socket.IO connection.
class SocketIoSender implements RealtimeConnectionSender {
  /// The underlying Socket.IO client.
  final Socket socket;

  /// The realtime session scope tracking this connection exchange.
  final RealtimeSessionScope scope;

  /// Creates a [SocketIoSender] binding [socket] and [scope].
  SocketIoSender(this.socket, this.scope);

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

    socket.emit(event, draft.payload);
  }
}
