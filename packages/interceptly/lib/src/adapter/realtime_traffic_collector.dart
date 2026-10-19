import 'dart:typed_data';

import '../capture/capture_guard.dart';
import '../capture/frame_normalizer.dart';
import '../model/realtime_frame.dart';
import '../model/realtime_protocol_type.dart';
import '../engine/interceptly_engine.dart';
import '../engine/request_id.dart';
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

  /// Explicitly marks realtime capability as active on the global collector's engine.
  static void markActive() {
    final current = instance;
    if (current is DefaultRealtimeTrafficCollector) {
      current.engine.markRealtimeActive();
    }
  }

  /// Maximum byte capacity for captured realtime frames.
  int get maxBodyBytes;

  /// Byte threshold above which realtime frame payloads should be offloaded to disk.
  int get offloadThreshold;

  /// Checks if [uri] is allowed to be captured according to current settings.
  bool shouldCapture(Uri? uri);

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
    RealtimeProtocolType protocolType = RealtimeProtocolType.webSocket,
  });

  /// Records an incoming or outgoing frame exchanged over an active connection.
  void recordFrame({
    required String sessionId,
    required FrameDirection direction,
    required FrameType type,
    required dynamic payload,
    int? payloadSizeBytes,
    DateTime? timestamp,
    String? shortPreview,
    bool? shouldOffload,
    String? eventName,
    Uint8List? preEncodedBytes,
  });

  /// Records the closure of an active realtime connection.
  void recordClose({
    required String sessionId,
    int? closeCode,
    String? closeReason,
  });
}

/// Default implementation of [RealtimeTrafficCollector] backed by [InterceptlyEngine].
class DefaultRealtimeTrafficCollector implements RealtimeTrafficCollector {
  /// Creates a collector backed by [engine] or [InterceptlyEngine.instance].
  DefaultRealtimeTrafficCollector({InterceptlyEngine? engine})
      : _customEngine = engine;

  final InterceptlyEngine? _customEngine;
  final Map<String, RealtimeSessionScope> _activeScopes = {};

  /// The underlying [InterceptlyEngine] used for storing captured traffic.
  InterceptlyEngine get engine => _customEngine ?? InterceptlyEngine.instance;

  @override
  int get maxBodyBytes => engine.settings.maxBodyBytes;

  @override
  int get offloadThreshold => engine.settings.realtimeBodyOffloadThreshold;

  @override
  bool shouldCapture(Uri? uri) {
    if (uri == null) return true;
    final predicate = engine.settings.shouldCapture;
    if (predicate == null) return true;
    return predicate(uri.toString());
  }

  @override
  RealtimeSessionScope openSession({
    Uri? uri,
    String? sessionId,
    Map<String, String>? headers,
    RealtimeProtocolType protocolType = RealtimeProtocolType.webSocket,
  }) {
    engine.markRealtimeActive();
    final effectiveId = sessionId ?? RequestId.generate();

    final isCaptured = shouldCapture(uri);

    if (uri != null && isCaptured) {
      guardCapture(() {
        engine.recordRealtimeConnection(
          id: effectiveId,
          url: uri.toString(),
          headers: headers ?? const {},
          isPreValidated: true,
          protocolType: protocolType,
        );
      });
    }

    final scope = RealtimeSessionScope(
      collector: this,
      sessionId: effectiveId,
      uri: uri,
      protocolType: protocolType,
      shouldCapture: isCaptured,
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
    RealtimeProtocolType protocolType = RealtimeProtocolType.webSocket,
  }) {
    if (!shouldCapture(uri)) {
      return;
    }
    guardCapture(() {
      engine.recordRealtimeConnection(
        id: sessionId,
        url: uri.toString(),
        headers: headers ?? const {},
        protocolType: protocolType,
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
    String? shortPreview,
    bool? shouldOffload,
    String? eventName,
    Uint8List? preEncodedBytes,
  }) {
    final normalized = (shortPreview != null && payloadSizeBytes != null)
        ? null
        : FrameNormalizer.normalize(
            payload,
            offloadThreshold: offloadThreshold,
            maxBodyBytes: maxBodyBytes,
            explicitType: type,
          );

    final effectiveType = normalized?.type ?? type;
    final effectivePayload = normalized?.payload ?? payload;
    final effectiveSize =
        normalized?.originalSizeBytes ?? payloadSizeBytes ?? 0;
    final effectivePreview = normalized?.shortPreview ?? shortPreview ?? '';
    final effectiveBytes = normalized?.preEncodedBytes ?? preEncodedBytes;

    String? textPayload;
    Uint8List? binaryPayload;

    if (effectiveType == FrameType.binary && effectivePayload is Uint8List) {
      binaryPayload = effectivePayload;
    } else if (effectiveType == FrameType.text && effectivePayload is String) {
      textPayload = effectivePayload;
    }

    final frame = RealtimeFrame(
      id: RequestId.generate(),
      sessionId: sessionId,
      direction: direction,
      type: effectiveType,
      textPayload: textPayload,
      binaryPayload: binaryPayload,
      shortPreview: effectivePreview,
      payloadSizeBytes: effectiveSize,
      timestamp: timestamp,
      eventName: eventName,
      preEncodedBytes: effectiveBytes,
    );

    engine.recordRealtimeFrame(frame);
  }

  @override
  void recordClose({
    required String sessionId,
    int? closeCode,
    String? closeReason,
  }) {
    _activeScopes.remove(sessionId);
    engine.closeRealtimeConnection(
      sessionId,
      closeCode: closeCode ?? 1000,
      closeReason: closeReason,
    );
  }
}
