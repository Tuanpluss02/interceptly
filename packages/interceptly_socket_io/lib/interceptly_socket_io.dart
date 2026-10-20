/// Socket.IO adapter for the Interceptly network inspector.
library;

export 'package:interceptly/adapter.dart'
    show RealtimeConnectionSender, RealtimeMessageDraft, RealtimeProtocolType;

export 'src/interceptly_socket_io.dart';
export 'src/socket_io_sender.dart';
export 'src/socket_io_tracker.dart';

/// The current version of interceptly_socket_io.
const String packageVersion = '1.0.0';
