import 'dart:typed_data';

import '../capture/capture_guard.dart';
import '../model/realtime_frame.dart';
import '../session/inspector_session.dart';
import '../session/request_id.dart';

/// Contract for coordinating realtime network traffic (WebSocket, SSE, Socket.IO).
abstract interface class RealtimeTrafficCollector {
  /// Records the establishment of a realtime connection (e.g. WebSocket handshake).
  void recordConnection({
    required String sessionId,
    required Uri uri,
    Map<String, String>? headers,
  });

  /// Records an incoming or outgoing frame exchanged over an active connection.
  void recordFrame({
    required String sessionId,
    required FrameDirection direction,
    required FrameType type,
    required dynamic payload,
    int? payloadSizeBytes,
    DateTime? timestamp,
  });

  /// Records the closure of an active realtime connection.
  void recordClose({
    required String sessionId,
    int? closeCode,
    String? closeReason,
  });
}

/// Default implementation of [RealtimeTrafficCollector] backed by [InspectorSession].
class DefaultRealtimeTrafficCollector implements RealtimeTrafficCollector {
  /// Creates a collector backed by [InspectorSession.instance].
  DefaultRealtimeTrafficCollector();

  /// The underlying [InspectorSession] used for storing captured traffic.
  InspectorSession get session => InspectorSession.instance;

  @override
  void recordConnection({
    required String sessionId,
    required Uri uri,
    Map<String, String>? headers,
  }) {
    guardCapture(() {
      session.recordRealtimeConnection(
        id: sessionId,
        url: uri.toString(),
        headers: headers ?? const {},
      );
    });
  }

  @override
  void recordFrame({
    required String sessionId,
    required FrameDirection direction,
    required FrameType type,
    required dynamic payload,
    int? payloadSizeBytes,
    DateTime? timestamp,
  }) {
    guardCapture(() {
      String? textPayload;
      Uint8List? binaryPayload;

      if (payload is String) {
        textPayload = payload;
      } else if (payload is Uint8List) {
        binaryPayload = payload;
      } else if (payload is List<int>) {
        binaryPayload = Uint8List.fromList(payload);
      } else if (payload != null) {
        textPayload = payload.toString();
      }

      final frame = RealtimeFrame(
        id: RequestId.generate(),
        sessionId: sessionId,
        direction: direction,
        type: type,
        textPayload: textPayload,
        binaryPayload: binaryPayload,
        payloadSizeBytes: payloadSizeBytes,
        timestamp: timestamp,
      );

      session.recordRealtimeFrame(frame);
    });
  }

  @override
  void recordClose({
    required String sessionId,
    int? closeCode,
    String? closeReason,
  }) {
    guardCapture(() {
      session.closeRealtimeConnection(
        sessionId,
        closeCode: closeCode ?? 1000,
        closeReason: closeReason,
      );
    });
  }
}
