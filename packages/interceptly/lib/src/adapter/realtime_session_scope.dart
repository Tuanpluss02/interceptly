import 'dart:convert';
import 'dart:typed_data';

import '../capture/body_bytes.dart';
import '../capture/capture_guard.dart';
import '../model/realtime_frame.dart';
import 'realtime_traffic_collector.dart';

/// Scope managing the lifecycle of an ongoing realtime connection (WebSocket, SSE).
class RealtimeSessionScope {
  /// Creates a [RealtimeSessionScope] for tracking traffic over [sessionId].
  RealtimeSessionScope({
    required this.collector,
    required this.sessionId,
    this.uri,
  });

  /// The collector coordinating storage.
  final RealtimeTrafficCollector collector;

  /// Unique identifier of this realtime connection session.
  final String sessionId;

  /// Target URI of the connection, if provided.
  final Uri? uri;

  bool _isClosed = false;

  /// Whether this session has been closed.
  bool get isClosed => _isClosed;

  /// Records an outgoing frame sent to the server. Safe to call.
  void send(dynamic data) {
    if (_isClosed) return;
    guardCapture(() => _record(data, FrameDirection.outgoing));
  }

  /// Records an incoming frame received from the server. Safe to call.
  void receive(dynamic data) {
    if (_isClosed) return;
    guardCapture(() => _record(data, FrameDirection.incoming));
  }

  /// Records the connection closure. Safe and idempotent.
  void close({int? code, String? reason}) {
    if (_isClosed) return;
    _isClosed = true;
    guardCapture(() {
      collector.recordClose(
        sessionId: sessionId,
        closeCode: code ?? 1000,
        closeReason: reason,
      );
    });
  }

  void _record(dynamic data, FrameDirection direction) {
    if (data == null) return;
    final maxBytes = collector.maxBodyBytes;

    if (data is Uint8List) {
      final original = data.length;
      final payload = (maxBytes > 0 && original > maxBytes)
          ? Uint8List.sublistView(data, 0, maxBytes)
          : data;
      collector.recordFrame(
        sessionId: sessionId,
        direction: direction,
        type: FrameType.binary,
        payload: payload,
        payloadSizeBytes: original,
      );
    } else if (data is ByteData) {
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final original = bytes.length;
      final payload = (maxBytes > 0 && original > maxBytes)
          ? Uint8List.sublistView(bytes, 0, maxBytes)
          : bytes;
      collector.recordFrame(
        sessionId: sessionId,
        direction: direction,
        type: FrameType.binary,
        payload: payload,
        payloadSizeBytes: original,
      );
    } else if (data is List<int>) {
      final bytes = Uint8List.fromList(data);
      final original = bytes.length;
      final payload = (maxBytes > 0 && original > maxBytes)
          ? Uint8List.sublistView(bytes, 0, maxBytes)
          : bytes;
      collector.recordFrame(
        sessionId: sessionId,
        direction: direction,
        type: FrameType.binary,
        payload: payload,
        payloadSizeBytes: original,
      );
    } else {
      final text = data is String ? data : data.toString();
      final originalBytes = utf8.encode(text).length;
      final payload = truncateUtf8(text, maxBytes);
      collector.recordFrame(
        sessionId: sessionId,
        direction: direction,
        type: FrameType.text,
        payload: payload,
        payloadSizeBytes: originalBytes,
      );
    }
  }
}
