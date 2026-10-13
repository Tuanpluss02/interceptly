import 'dart:convert';
import 'dart:typed_data';

/// The direction of a realtime frame relative to the client.
enum FrameDirection {
  /// Message received from the server.
  incoming,

  /// Message sent to the server.
  outgoing,
}

/// The protocol payload type or frame control code.
enum FrameType {
  /// UTF-8 or text encoded message.
  text,

  /// Raw binary encoded message.
  binary,

  /// Protocol keep-alive ping frame.
  ping,

  /// Protocol keep-alive pong response frame.
  pong,

  /// Channel / session disconnect frame.
  close,

  /// Protocol-level acknowledgement frame (e.g. Socket.IO ACK).
  ack,
}

/// Represents an individual message/frame exchanged over a realtime connection
/// (e.g. WebSocket, SSE, Socket.IO).
class RealtimeFrame {
  /// Creates a [RealtimeFrame] with automatic computation of [payloadSizeBytes]
  /// if not explicitly supplied.
  RealtimeFrame({
    required this.id,
    required this.sessionId,
    required this.direction,
    required this.type,
    this.textPayload,
    this.binaryPayload,
    int? payloadSizeBytes,
    DateTime? timestamp,
  })  : payloadSizeBytes = payloadSizeBytes ??
            (binaryPayload != null
                ? binaryPayload.lengthInBytes
                : (textPayload != null ? utf8.encode(textPayload).length : 0)),
        timestamp = timestamp ?? DateTime.now();

  /// Raw const constructor for zero-overhead initialization.
  const RealtimeFrame.raw({
    required this.id,
    required this.sessionId,
    required this.direction,
    required this.type,
    required this.payloadSizeBytes,
    required this.timestamp,
    this.textPayload,
    this.binaryPayload,
  });

  /// Convenience factory for creating a text frame.
  factory RealtimeFrame.text({
    required String id,
    required String sessionId,
    required FrameDirection direction,
    required String text,
    DateTime? timestamp,
    int? payloadSizeBytes,
  }) {
    return RealtimeFrame(
      id: id,
      sessionId: sessionId,
      direction: direction,
      type: FrameType.text,
      textPayload: text,
      payloadSizeBytes: payloadSizeBytes,
      timestamp: timestamp,
    );
  }

  /// Convenience factory for creating a binary frame.
  factory RealtimeFrame.binary({
    required String id,
    required String sessionId,
    required FrameDirection direction,
    required Uint8List bytes,
    DateTime? timestamp,
    int? payloadSizeBytes,
  }) {
    return RealtimeFrame(
      id: id,
      sessionId: sessionId,
      direction: direction,
      type: FrameType.binary,
      binaryPayload: bytes,
      payloadSizeBytes: payloadSizeBytes,
      timestamp: timestamp,
    );
  }

  /// Unique identifier for this frame.
  final String id;

  /// Identifier of the parent realtime session/connection.
  final String sessionId;

  /// Whether this frame was incoming or outgoing.
  final FrameDirection direction;

  /// Frame type (text, binary, ping, pong, close, ack).
  final FrameType type;

  /// String content when [type] == [FrameType.text], or null otherwise.
  final String? textPayload;

  /// Raw byte buffer when [type] == [FrameType.binary], or null otherwise.
  final Uint8List? binaryPayload;

  /// Total size of the payload in bytes.
  final int payloadSizeBytes;

  /// When this frame was captured.
  final DateTime timestamp;

  /// True if this is a text message frame.
  bool get isText => type == FrameType.text;

  /// True if this is a binary message frame.
  bool get isBinary => type == FrameType.binary;

  /// True if this frame was received from the server.
  bool get isIncoming => direction == FrameDirection.incoming;

  /// True if this frame was sent to the server.
  bool get isOutgoing => direction == FrameDirection.outgoing;

  /// True if this frame is a ping.
  bool get isPing => type == FrameType.ping;

  /// True if this frame is a pong.
  bool get isPong => type == FrameType.pong;

  /// True if this frame is a close frame.
  bool get isClose => type == FrameType.close;

  /// True if this frame is an ack frame.
  bool get isAck => type == FrameType.ack;

  /// Returns a copy of this frame with given fields replaced.
  RealtimeFrame copyWith({
    String? id,
    String? sessionId,
    FrameDirection? direction,
    FrameType? type,
    String? textPayload,
    Uint8List? binaryPayload,
    int? payloadSizeBytes,
    DateTime? timestamp,
  }) {
    return RealtimeFrame(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      direction: direction ?? this.direction,
      type: type ?? this.type,
      textPayload: textPayload ?? this.textPayload,
      binaryPayload: binaryPayload ?? this.binaryPayload,
      payloadSizeBytes: payloadSizeBytes ?? this.payloadSizeBytes,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() {
    return 'RealtimeFrame(id: $id, sessionId: $sessionId, direction: $direction, '
        'type: $type, payloadSizeBytes: $payloadSizeBytes, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RealtimeFrame &&
        other.id == id &&
        other.sessionId == sessionId &&
        other.direction == direction &&
        other.type == type &&
        other.textPayload == textPayload &&
        other.payloadSizeBytes == payloadSizeBytes &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(
        id,
        sessionId,
        direction,
        type,
        textPayload,
        payloadSizeBytes,
        timestamp,
      );
}
