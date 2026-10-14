import 'dart:convert';
import 'dart:typed_data';

import '../capture/capture_guard.dart';
import '../model/interceptly_settings.dart';
import '../model/realtime_frame.dart';
import '../session/capture_pipeline.dart';
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
  /// Creates a collector backed by [session] (defaults to [InspectorSession.instance]).
  DefaultRealtimeTrafficCollector([InspectorSession? session])
      : _session = session ?? InspectorSession.instance;

  final InspectorSession _session;

  /// The underlying [InspectorSession] used for storing captured traffic.
  InspectorSession get session => _session;

  @override
  void recordConnection({
    required String sessionId,
    required Uri uri,
    Map<String, String>? headers,
  }) {
    guardCapture(() {
      _session.recordRealtimeConnection(
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
      final BodyRedactor? redactor = _session.settings.bodyRedactor;
      String? textPayload;
      Uint8List? binaryPayload;

      if (payload is String) {
        textPayload = _redactText(payload, redactor);
      } else if (payload is Uint8List) {
        binaryPayload = CapturePipeline.redactInlineBytes(payload, redactor);
      } else if (payload is List<int>) {
        binaryPayload = CapturePipeline.redactInlineBytes(
          Uint8List.fromList(payload),
          redactor,
        );
      } else if (payload != null) {
        textPayload = _redactText(payload.toString(), redactor);
      }

      final frame = RealtimeFrame(
        id: RequestId.generate(),
        sessionId: sessionId,
        direction: direction,
        type: type,
        textPayload: textPayload,
        binaryPayload: binaryPayload,
        payloadSizeBytes: redactor == null ? payloadSizeBytes : null,
        timestamp: timestamp,
      );

      _session.recordRealtimeFrame(frame);
    });
  }

  @override
  void recordClose({
    required String sessionId,
    int? closeCode,
    String? closeReason,
  }) {
    guardCapture(() {
      _session.closeRealtimeConnection(
        sessionId,
        closeCode: closeCode ?? 1000,
        closeReason: closeReason,
      );
    });
  }
}

/// Encodes [text] to bytes, applies [redactor], and decodes tolerantly.
///
/// Returns the original [text] when no redactor is set or any step fails.
/// A null redactor result propagates as null so stripped bodies stay stripped.
String? _redactText(String text, BodyRedactor? redactor) {
  if (redactor == null) return text;
  try {
    final Uint8List? redacted = CapturePipeline.redactInlineBytes(
      Uint8List.fromList(utf8.encode(text)),
      redactor,
    );
    if (redacted == null) return null;
    return utf8.decode(redacted, allowMalformed: true);
  } catch (_) {
    return text;
  }
}
