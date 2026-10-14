import 'dart:typed_data';

import '../capture/capture_guard.dart';
import '../model/realtime_frame.dart';
import '../model/realtime_protocol_type.dart';
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

  /// Explicitly marks realtime capability as active on the global collector's session.
  static void markActive() {
    final current = instance;
    if (current is DefaultRealtimeTrafficCollector) {
      current.session.markRealtimeActive();
    }
  }

  /// Maximum byte capacity for captured realtime frames.
  int get maxBodyBytes;

  /// Opens and returns a [RealtimeSessionScope] for tracking an active connection.
  RealtimeSessionScope openSession({
    Uri? uri,
    String? sessionId,
    Map<String, String>? headers,
    RealtimeProtocolType protocolType = RealtimeProtocolType.webSocket,
  });

  /// Whether message transmission is currently permitted on [sessionId].
  bool canSend(String sessionId);

  /// Returns the active [RealtimeConnectionSender] for [sessionId], if attached.
  RealtimeConnectionSender? getSender(String sessionId);

  /// Transmits [draft] through the active sender registered for [sessionId].
  Future<void> sendMessage(String sessionId, RealtimeMessageDraft draft);

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
  final Map<String, RealtimeSessionScope> _activeScopes = {};

  /// The underlying [InspectorSession] used for storing captured traffic.
  InspectorSession get session => _customSession ?? InspectorSession.instance;

  @override
  int get maxBodyBytes => session.settings.maxBodyBytes;

  @override
  RealtimeSessionScope openSession({
    Uri? uri,
    String? sessionId,
    Map<String, String>? headers,
    RealtimeProtocolType protocolType = RealtimeProtocolType.webSocket,
  }) {
    session.markRealtimeActive();
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

    final scope = RealtimeSessionScope(
      collector: this,
      sessionId: effectiveId,
      uri: uri,
      protocolType: protocolType,
    );
    _activeScopes[effectiveId] = scope;
    return scope;
  }

  @override
  bool canSend(String sessionId) => _activeScopes[sessionId]?.canSend ?? false;

  @override
  RealtimeConnectionSender? getSender(String sessionId) =>
      _activeScopes[sessionId]?.sender;

  @override
  Future<void> sendMessage(String sessionId, RealtimeMessageDraft draft) async {
    final scope = _activeScopes[sessionId];
    if (scope == null) {
      throw StateError(
        'Cannot send message: no active session found for id $sessionId',
      );
    }
    await scope.sendToServer(draft);
  }

  @override
  void recordConnection({
    required String sessionId,
    required Uri uri,
    Map<String, String>? headers,
  }) {
    if (session.settings.shouldCapture != null &&
        !session.settings.shouldCapture!(uri.toString())) {
      return;
    }
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
      int? effectiveSize = payloadSizeBytes;

      if (payload is String) {
        textPayload = payload;
      } else if (payload is Uint8List) {
        binaryPayload = Uint8List.fromList(payload);
      } else if (payload is List<int>) {
        binaryPayload = Uint8List.fromList(payload);
      } else if (payload != null) {
        textPayload = payload.toString();
      }

      final maxBytes = maxBodyBytes;
      if (maxBytes > 0) {
        if (binaryPayload != null) {
          effectiveSize ??= binaryPayload.lengthInBytes;
          if (binaryPayload.length > maxBytes) {
            binaryPayload = Uint8List.sublistView(binaryPayload, 0, maxBytes);
          }
        } else if (textPayload != null) {
          effectiveSize ??= utf8ByteLength(textPayload);
          if (textPayload.length > maxBytes) {
            textPayload = textPayload.substring(0, maxBytes);
          }
        }
      }

      final frame = RealtimeFrame(
        id: RequestId.generate(),
        sessionId: sessionId,
        direction: direction,
        type: type,
        textPayload: textPayload,
        binaryPayload: binaryPayload,
        payloadSizeBytes: effectiveSize,
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
    _activeScopes.remove(sessionId);
    guardCapture(() {
      session.closeRealtimeConnection(
        sessionId,
        closeCode: closeCode ?? 1000,
        closeReason: closeReason,
      );
    });
  }
}
