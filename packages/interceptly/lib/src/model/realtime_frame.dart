import 'dart:typed_data';

import 'package:interceptly/src/model/body_location.dart';

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
  /// and [shortPreview] if not explicitly supplied.
  RealtimeFrame({
    required this.id,
    required this.sessionId,
    required this.direction,
    required this.type,
    this.location = BodyLocation.memory,
    this.textPayload,
    this.binaryPayload,
    String? shortPreview,
    this.fileOffset,
    this.fileLength,
    this.rotationCount,
    this.eventName,
    int? payloadSizeBytes,
    DateTime? timestamp,
  })  : shortPreview = shortPreview ??
            extractShortPreview(textPayload ?? binaryPayload, type),
        payloadSizeBytes = payloadSizeBytes ??
            fileLength ??
            binaryPayload?.lengthInBytes ??
            (textPayload != null ? utf8ByteLength(textPayload) : 0),
        timestamp = timestamp ?? DateTime.now();

  /// Raw const constructor for zero-overhead initialization.
  const RealtimeFrame.raw({
    required this.id,
    required this.sessionId,
    required this.direction,
    required this.type,
    required this.location,
    required this.shortPreview,
    required this.payloadSizeBytes,
    required this.timestamp,
    this.textPayload,
    this.binaryPayload,
    this.fileOffset,
    this.fileLength,
    this.rotationCount,
    this.eventName,
  });

  /// Convenience factory for creating a text frame retained in memory.
  factory RealtimeFrame.memoryText({
    required String id,
    required String sessionId,
    required FrameDirection direction,
    required String text,
    String? eventName,
    DateTime? timestamp,
    int? payloadSizeBytes,
    String? shortPreview,
  }) {
    return RealtimeFrame(
      id: id,
      sessionId: sessionId,
      direction: direction,
      type: FrameType.text,
      location: BodyLocation.memory,
      textPayload: text,
      eventName: eventName,
      payloadSizeBytes: payloadSizeBytes,
      timestamp: timestamp,
      shortPreview: shortPreview,
    );
  }

  /// Convenience factory for creating a binary frame retained in memory.
  factory RealtimeFrame.memoryBinary({
    required String id,
    required String sessionId,
    required FrameDirection direction,
    required Uint8List bytes,
    String? eventName,
    DateTime? timestamp,
    int? payloadSizeBytes,
    String? shortPreview,
  }) {
    return RealtimeFrame(
      id: id,
      sessionId: sessionId,
      direction: direction,
      type: FrameType.binary,
      location: BodyLocation.memory,
      binaryPayload: bytes,
      eventName: eventName,
      payloadSizeBytes: payloadSizeBytes,
      timestamp: timestamp,
      shortPreview: shortPreview,
    );
  }

  /// Convenience factory for creating an offloaded frame persisted to disk.
  factory RealtimeFrame.offloaded({
    required String id,
    required String sessionId,
    required FrameDirection direction,
    required FrameType type,
    required int payloadSizeBytes,
    required String shortPreview,
    required int fileOffset,
    required int fileLength,
    required int rotationCount,
    String? eventName,
    DateTime? timestamp,
  }) {
    return RealtimeFrame(
      id: id,
      sessionId: sessionId,
      direction: direction,
      type: type,
      location: BodyLocation.file,
      shortPreview: shortPreview,
      fileOffset: fileOffset,
      fileLength: fileLength,
      rotationCount: rotationCount,
      payloadSizeBytes: payloadSizeBytes,
      eventName: eventName,
      timestamp: timestamp,
    );
  }

  /// Alias for [RealtimeFrame.memoryText].
  factory RealtimeFrame.text({
    required String id,
    required String sessionId,
    required FrameDirection direction,
    required String text,
    String? eventName,
    DateTime? timestamp,
    int? payloadSizeBytes,
    String? shortPreview,
  }) = RealtimeFrame.memoryText;

  /// Alias for [RealtimeFrame.memoryBinary].
  factory RealtimeFrame.binary({
    required String id,
    required String sessionId,
    required FrameDirection direction,
    required Uint8List bytes,
    String? eventName,
    DateTime? timestamp,
    int? payloadSizeBytes,
    String? shortPreview,
  }) = RealtimeFrame.memoryBinary;

  /// Unique identifier for this frame.
  final String id;

  /// Identifier of the parent realtime session/connection.
  final String sessionId;

  /// Whether this frame was incoming or outgoing.
  final FrameDirection direction;

  /// Frame type (text, binary, ping, pong, close, ack).
  final FrameType type;

  /// Storage location of the full payload (memory vs offloaded to file).
  final BodyLocation location;

  /// String content when [type] == [FrameType.text] and [location] == [BodyLocation.memory].
  final String? textPayload;

  /// Raw byte buffer when [type] == [FrameType.binary] and [location] == [BodyLocation.memory].
  final Uint8List? binaryPayload;

  /// Lightweight short preview (<= 128 characters, safe Unicode) always retained in RAM.
  final String shortPreview;

  /// Offset in the realtime temp file if offloaded to disk.
  final int? fileOffset;

  /// Length of the offloaded payload in bytes if offloaded to disk.
  final int? fileLength;

  /// Generational rotation count from [RealtimeBodyStore] to detect file rotation.
  final int? rotationCount;

  /// Optional event name for event-driven realtime protocols (e.g. Socket.IO).
  final String? eventName;

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

  /// True if this frame payload has been offloaded to disk.
  bool get isOffloaded => location == BodyLocation.file;

  /// True if this frame payload is resident in memory.
  bool get isMemory => location == BodyLocation.memory;

  /// Extracts a safe, concise short preview from [payload] without splitting UTF-16 surrogate pairs.
  static String extractShortPreview(
    dynamic payload,
    FrameType type, {
    int maxChars = 128,
  }) {
    if (payload == null) {
      return type.name.toUpperCase();
    }
    if (payload is Uint8List) {
      if (payload.isEmpty) return '[empty binary]';
      final sample = payload
          .take(16)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      final suffix = payload.length > 16 ? '...' : '';
      return '[binary: ${payload.length} bytes] $sample$suffix';
    }
    if (type == FrameType.binary && payload is List<int>) {
      if (payload.isEmpty) return '[empty binary]';
      final sample = payload
          .take(16)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      final suffix = payload.length > 16 ? '...' : '';
      return '[binary: ${payload.length} bytes] $sample$suffix';
    }
    final text = payload is String ? payload : payload.toString();
    if (text.length <= maxChars) {
      return text;
    }
    // Prevent splitting a UTF-16 surrogate pair
    if (maxChars > 0 &&
        text.codeUnitAt(maxChars - 1) >= 0xD800 &&
        text.codeUnitAt(maxChars - 1) <= 0xDBFF) {
      return text.substring(0, maxChars - 1);
    }
    return text.substring(0, maxChars);
  }

  /// Returns a copy of this frame with given fields replaced.
  RealtimeFrame copyWith({
    String? id,
    String? sessionId,
    FrameDirection? direction,
    FrameType? type,
    BodyLocation? location,
    String? textPayload,
    Uint8List? binaryPayload,
    String? shortPreview,
    int? fileOffset,
    int? fileLength,
    int? rotationCount,
    String? eventName,
    int? payloadSizeBytes,
    DateTime? timestamp,
  }) {
    return RealtimeFrame(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      direction: direction ?? this.direction,
      type: type ?? this.type,
      location: location ?? this.location,
      textPayload: textPayload ?? this.textPayload,
      binaryPayload: binaryPayload ?? this.binaryPayload,
      shortPreview: shortPreview ?? this.shortPreview,
      fileOffset: fileOffset ?? this.fileOffset,
      fileLength: fileLength ?? this.fileLength,
      rotationCount: rotationCount ?? this.rotationCount,
      eventName: eventName ?? this.eventName,
      payloadSizeBytes: payloadSizeBytes ?? this.payloadSizeBytes,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() {
    return 'RealtimeFrame(id: $id, sessionId: $sessionId, direction: $direction, '
        'type: $type, location: $location, eventName: $eventName, payloadSizeBytes: $payloadSizeBytes, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RealtimeFrame &&
        other.id == id &&
        other.sessionId == sessionId &&
        other.direction == direction &&
        other.type == type &&
        other.location == location &&
        other.textPayload == textPayload &&
        identical(binaryPayload, other.binaryPayload) &&
        other.shortPreview == shortPreview &&
        other.fileOffset == fileOffset &&
        other.fileLength == fileLength &&
        other.rotationCount == rotationCount &&
        other.eventName == eventName &&
        other.payloadSizeBytes == payloadSizeBytes &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(
        id,
        sessionId,
        direction,
        type,
        location,
        textPayload,
        binaryPayload,
        shortPreview,
        fileOffset,
        fileLength,
        rotationCount,
        eventName,
        payloadSizeBytes,
        timestamp,
      );
}

/// Computes the UTF-8 byte length of [text] without allocating a byte array.
int utf8ByteLength(String text) {
  var bytes = 0;
  final len = text.length;
  for (var i = 0; i < len; i++) {
    final codeUnit = text.codeUnitAt(i);
    if (codeUnit <= 0x007F) {
      bytes += 1;
    } else if (codeUnit <= 0x07FF) {
      bytes += 2;
    } else if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF) {
      if (i + 1 < len) {
        final nextUnit = text.codeUnitAt(i + 1);
        if (nextUnit >= 0xDC00 && nextUnit <= 0xDFFF) {
          bytes += 4;
          i++;
          continue;
        }
      }
      bytes += 3;
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

/// Tracks the count of frames received (incoming) and sent (outgoing) for a realtime session.
class RealtimeFrameCounts {
  const RealtimeFrameCounts({this.incoming = 0, this.outgoing = 0});

  /// Total number of incoming frames received from the server.
  final int incoming;

  /// Total number of outgoing frames sent to the server.
  final int outgoing;

  /// Combined total of incoming and outgoing frames.
  int get total => incoming + outgoing;

  /// Returns a copy of [RealtimeFrameCounts] incremented for [direction].
  RealtimeFrameCounts copyWithIncrement({required FrameDirection direction}) {
    if (direction == FrameDirection.incoming) {
      return RealtimeFrameCounts(incoming: incoming + 1, outgoing: outgoing);
    } else {
      return RealtimeFrameCounts(incoming: incoming, outgoing: outgoing + 1);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RealtimeFrameCounts &&
          other.incoming == incoming &&
          other.outgoing == outgoing;

  @override
  int get hashCode => Object.hash(incoming, outgoing);

  @override
  String toString() =>
      'RealtimeFrameCounts(incoming: $incoming, outgoing: $outgoing)';
}
