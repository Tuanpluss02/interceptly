import 'dart:typed_data';

import '../capture/capture_guard.dart';
import '../model/realtime_frame.dart';
import '../session/inspector_session.dart';
import '../session/request_id.dart';
import 'realtime_session_scope.dart';

/// Contract for coordinating realtime network traffic (WebSocket, SSE, Socket.IO).
abstract interface class RealtimeTrafficCollector {
  static RealtimeTrafficCollector? _instance;

  /// The active global [RealtimeTrafficCollector] instance.
  static RealtimeTrafficCollector get instance =>
      _instance ??= DefaultRealtimeTrafficCollector();

  /// Overrides the global [RealtimeTrafficCollector] instance (e.g. for testing).
  static set instance(RealtimeTrafficCollector collector) {
    _instance = collector;
  }

  /// Maximum byte capacity for captured realtime frames.
  int get maxBodyBytes;

  /// Opens and returns a [RealtimeSessionScope] for tracking an active connection.
  RealtimeSessionScope openSession({
    Uri? uri,
    String? sessionId,
    Map<String, String>? headers,
  });

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
  /// Creates a collector backed by [session] or [InspectorSession.instance].
  DefaultRealtimeTrafficCollector({InspectorSession? session})
      : _customSession = session;

  final InspectorSession? _customSession;

  /// The underlying [InspectorSession] used for storing captured traffic.
  InspectorSession get session => _customSession ?? InspectorSession.instance;

  @override
  int get maxBodyBytes => session.settings.maxBodyBytes;

  @override
  RealtimeSessionScope openSession({
    Uri? uri,
    String? sessionId,
    Map<String, String>? headers,
  }) {
    final effectiveId = sessionId ?? RequestId.generate();

    if (uri != null) {
      guardCapture(() {
        recordConnection(
          sessionId: effectiveId,
          uri: uri,
          headers: headers,
        );
      });
    }

    return RealtimeSessionScope(
      collector: this,
      sessionId: effectiveId,
      uri: uri,
    );
  }

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
