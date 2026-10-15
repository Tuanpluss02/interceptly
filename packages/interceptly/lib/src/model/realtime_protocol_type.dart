/// Supported realtime connection protocols for Interceptly.
enum RealtimeProtocolType {
  /// Raw duplex frame stream (RFC 6455).
  webSocket,

  /// Event-driven bidirectional communication over Engine.IO.
  socketIo,

  /// Unidirectional server-to-client event stream.
  sse,
}

/// Represents a message or event ready to be sent across a realtime connection.
class RealtimeMessageDraft {
  /// The event name (required/primary for Socket.IO, null for raw WebSocket).
  final String? event;

  /// The message payload (String, JSON Map/List, or Uint8List).
  final dynamic payload;

  /// Creates a draft message with optional [event] and required [payload].
  const RealtimeMessageDraft({
    this.event,
    required this.payload,
  });

  /// Helper to convert payload into a readable text string for editors.
  String get payloadText {
    if (payload is String) return payload as String;
    if (payload == null) return '';
    return payload.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RealtimeMessageDraft &&
          other.event == event &&
          other.payload == payload;

  @override
  int get hashCode => Object.hash(event, payload);

  @override
  String toString() => 'RealtimeMessageDraft(event: $event, payload: $payload)';
}

/// Contract implemented by realtime adapters to handle message transmission.
abstract interface class RealtimeConnectionSender {
  /// The protocol type this sender handles.
  RealtimeProtocolType get protocolType;

  /// Whether sending is currently permitted (e.g. connection is open and writable).
  bool get canSend;

  /// Transmits the given [draft] through the underlying connection sink/client.
  Future<void> send(RealtimeMessageDraft draft);
}
