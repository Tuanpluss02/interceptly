import 'package:interceptly/adapter.dart';
import 'package:socket_io_client/socket_io_client.dart';

import 'socket_io_sender.dart';
import 'socket_io_tracker.dart';

/// Entry point for attaching Interceptly network inspection to Socket.IO clients.
///
/// Repeated attaches for the same [Socket] return the existing tracker so
/// a socket never yields duplicate sessions or listeners.
class InterceptlySocketIo {
  InterceptlySocketIo._();

  static final Expando<InterceptlySocketIoTracker> _trackers =
      Expando<InterceptlySocketIoTracker>('interceptly_socket_io');

  /// Attaches Interceptly network capture to [socket].
  ///
  /// Listens to incoming and outgoing events, records connection lifecycle,
  /// and enables interactive event emission and replay from the Interceptly UI.
  static InterceptlySocketIoTracker attach(
    Socket socket, {
    Uri? uri,
    Map<String, String>? headers,
    String? sessionId,
    RealtimeTrafficCollector? collector,
  }) {
    final existing = _trackers[socket];
    if (existing != null && !existing.isDetached) {
      return existing;
    }
    final effectiveCollector = collector ?? RealtimeTrafficCollector.instance;
    final resolvedUri = _resolveUri(socket, uri);

    final scope = effectiveCollector.openSession(
      uri: resolvedUri,
      protocolType: RealtimeProtocolType.socketIo,
      headers: headers,
      sessionId: sessionId,
    );

    final tracker = InterceptlySocketIoTracker(
      socket: socket,
      scope: scope,
      collector: effectiveCollector,
      uri: resolvedUri,
      headers: headers,
    );

    final sender = SocketIoSender.dynamic(socket, () => tracker.scope);
    scope.attachSender(sender);

    _trackers[socket] = tracker;
    return tracker;
  }

  static Uri _resolveUri(Socket socket, Uri? explicitUri) {
    if (explicitUri != null) return explicitUri;
    try {
      final rawUri = socket.io.uri;
      final parsed = Uri.tryParse(rawUri);
      if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
        if (socket.nsp.isNotEmpty &&
            socket.nsp != '/' &&
            !parsed.path.endsWith(socket.nsp)) {
          final newPath = parsed.path.endsWith('/')
              ? '${parsed.path}${socket.nsp.substring(1)}'
              : '${parsed.path}${socket.nsp}';
          return parsed.replace(path: newPath);
        }
        return parsed;
      }
    } catch (_) {}

    try {
      final nsp = socket.nsp;
      return Uri(
        scheme: 'http',
        host: 'socket-io',
        path: nsp.isNotEmpty ? nsp : '/',
      );
    } catch (_) {
      return Uri(scheme: 'http', host: 'socket-io', path: '/');
    }
  }
}

/// Extension on [Socket] for convenient Interceptly inspector attachment.
extension InterceptlySocketIoExtension on Socket {
  /// Attaches Interceptly network capture to this [Socket].
  InterceptlySocketIoTracker attachInterceptly({
    Uri? uri,
    Map<String, String>? headers,
    String? sessionId,
    RealtimeTrafficCollector? collector,
  }) =>
      InterceptlySocketIo.attach(
        this,
        uri: uri,
        headers: headers,
        sessionId: sessionId,
        collector: collector,
      );
}
