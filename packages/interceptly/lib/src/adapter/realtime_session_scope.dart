import '../capture/capture_guard.dart';
import '../capture/frame_normalizer.dart';
import '../model/realtime_frame.dart';
import '../model/realtime_protocol_type.dart';
import 'realtime_traffic_collector.dart';

/// Scope managing the lifecycle of an ongoing realtime connection (WebSocket, SSE).
class RealtimeSessionScope {
  /// Creates a [RealtimeSessionScope] for tracking traffic over [sessionId].
  RealtimeSessionScope({
    required this.collector,
    required this.sessionId,
    this.uri,
    this.protocolType = RealtimeProtocolType.webSocket,
    bool? shouldCapture,
  }) : _shouldCapture = shouldCapture ?? collector.shouldCapture(uri);

  /// The collector coordinating storage.
  final RealtimeTrafficCollector collector;

  /// Unique identifier of this realtime connection session.
  final String sessionId;

  /// Target URI of the connection, if provided.
  final Uri? uri;

  /// Protocol type for this realtime connection.
  final RealtimeProtocolType protocolType;

  /// Cached evaluation of shouldCapture evaluated once at connection handshake.
  final bool _shouldCapture;

  RealtimeConnectionSender? _sender;
  bool _isClosed = false;

  /// Whether this session has been closed.
  bool get isClosed => _isClosed;

  /// The active sender delegate, if attached.
  RealtimeConnectionSender? get sender => _sender;

  /// Whether message transmission is currently permitted.
  bool get canSend => !_isClosed && (_sender?.canSend ?? false);

  /// Attaches a [sender] capable of transmitting messages over this connection.
  void attachSender(RealtimeConnectionSender sender) {
    if (_isClosed) return;
    _sender = sender;
  }

  /// Detaches the current sender delegate.
  void detachSender() {
    _sender = null;
  }

  /// Transmits [draft] through the attached sender to the server.
  Future<void> sendToServer(RealtimeMessageDraft draft) async {
    if (!canSend || _sender == null) {
      throw StateError(
        'Cannot send message: connection is closed or sender unavailable',
      );
    }
    await _sender!.send(draft);
  }

  /// Records an outgoing frame sent to the server. Safe to call.
  void send(dynamic data, {String? eventName}) {
    if (_isClosed || !_shouldCapture) return;
    guardCapture(
        () => _record(data, FrameDirection.outgoing, eventName: eventName));
  }

  /// Records an incoming frame received from the server. Safe to call.
  void receive(dynamic data, {String? eventName}) {
    if (_isClosed || !_shouldCapture) return;
    guardCapture(
        () => _record(data, FrameDirection.incoming, eventName: eventName));
  }

  /// Records the connection closure. Safe and idempotent.
  void close({int? code, String? reason}) {
    if (_isClosed) return;
    _isClosed = true;
    detachSender();
    guardCapture(() {
      collector.recordClose(
        sessionId: sessionId,
        closeCode: code ?? 1000,
        closeReason: reason,
      );
    });
  }

  /// Normalizes [data] once and forwards the computed preview and size
  /// so [RealtimeTrafficCollector.recordFrame] hits its fast path without
  /// renormalizing the payload.
  void _record(dynamic data, FrameDirection direction, {String? eventName}) {
    if (data == null) return;
    final normalized = FrameNormalizer.normalize(
      data,
      offloadThreshold: collector.offloadThreshold,
      maxBodyBytes: collector.maxBodyBytes,
    );

    collector.recordFrame(
      sessionId: sessionId,
      direction: direction,
      type: normalized.type,
      payload: normalized.payload,
      payloadSizeBytes: normalized.originalSizeBytes,
      shortPreview: normalized.shortPreview,
      shouldOffload: normalized.shouldOffload,
      eventName: eventName,
      preEncodedBytes: normalized.preEncodedBytes,
    );
  }
}
