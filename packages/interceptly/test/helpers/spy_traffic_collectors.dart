import 'dart:async';
import 'dart:typed_data';

import 'package:interceptly/adapter.dart';

/// Test spy implementation of [HttpTrafficCollector] for verifying adapter interactions.
class SpyHttpTrafficCollector implements HttpTrafficCollector {
  @override
  int maxBodyBytes;

  Duration Function(int chunkBytes)? chunkDelayProvider;
  bool Function(Uri? uri)? shouldCaptureProvider;
  bool shouldCaptureDefault;
  bool throwSimulatedException;
  bool returnNullContext;
  HttpRequestContext? nextContext;

  final List<Map<String, dynamic>> beginCalls = [];
  final List<Map<String, dynamic>> startRequestCalls = [];
  final List<Map<String, dynamic>> completeResponseCalls = [];
  final List<Map<String, dynamic>> failRequestCalls = [];

  SpyHttpTrafficCollector({
    this.maxBodyBytes = 1024 * 1024,
    this.shouldCaptureDefault = true,
    this.throwSimulatedException = false,
    this.returnNullContext = false,
    this.nextContext,
    this.chunkDelayProvider,
    this.shouldCaptureProvider,
  });

  @override
  Duration delayForChunk(int chunkBytes) =>
      chunkDelayProvider?.call(chunkBytes) ?? Duration.zero;

  @override
  bool shouldCapture(Uri? uri) =>
      shouldCaptureProvider?.call(uri) ?? shouldCaptureDefault;

  @override
  Future<HttpCaptureScope> begin({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    String? contentType,
    String? requestId,
  }) async {
    beginCalls.add({
      'method': method,
      'uri': uri,
      'headers': headers,
      'bodyBytes': bodyBytes,
      'contentType': contentType,
      'requestId': requestId,
    });
    final context = await startRequest(
      method: method,
      uri: uri,
      headers: headers,
      bodyBytes: bodyBytes,
      contentType: contentType,
      requestId: requestId,
    );
    return HttpCaptureScope(collector: this, context: context);
  }

  @override
  Future<HttpRequestContext?> startRequest({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    String? contentType,
    String? requestId,
  }) async {
    startRequestCalls.add({
      'method': method,
      'uri': uri,
      'headers': headers,
      'bodyBytes': bodyBytes,
      'contentType': contentType,
      'requestId': requestId,
    });

    if (throwSimulatedException) {
      throw const SimulatedNetworkException('Pre-request simulation: offline');
    }

    if (returnNullContext) {
      return null;
    }

    return nextContext ??
        HttpRequestContext(
          id: requestId ?? RequestId.generate(),
          method: method,
          uri: uri,
          startedAt: DateTime.now(),
          requestHeaders: headers ?? const {},
          requestBodyBytes: bodyBytes,
          requestContentType: contentType,
        );
  }

  @override
  Future<void> completeResponse({
    required HttpRequestContext context,
    required int statusCode,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    int? responseSizeBytes,
    int? durationMs,
    String? responseContentType,
    bool? responseTruncatedAtStorage,
  }) async {
    completeResponseCalls.add({
      'context': context,
      'statusCode': statusCode,
      'headers': headers,
      'bodyBytes': bodyBytes,
      'responseSizeBytes': responseSizeBytes,
      'durationMs': durationMs,
      'responseContentType': responseContentType,
      'responseTruncatedAtStorage': responseTruncatedAtStorage,
    });
  }

  @override
  void failRequest({
    required HttpRequestContext context,
    required Object error,
    String? errorType,
    String? errorMessage,
    int? statusCode,
    Map<String, String>? responseHeaders,
    Uint8List? responseBodyBytes,
    int? responseSizeBytes,
    int? durationMs,
    bool? responseTruncatedAtStorage,
  }) {
    failRequestCalls.add({
      'context': context,
      'error': error,
      'errorType': errorType,
      'errorMessage': errorMessage,
      'statusCode': statusCode,
      'responseHeaders': responseHeaders,
      'responseBodyBytes': responseBodyBytes,
      'responseSizeBytes': responseSizeBytes,
      'durationMs': durationMs,
      'responseTruncatedAtStorage': responseTruncatedAtStorage,
    });
  }

  void reset() {
    beginCalls.clear();
    startRequestCalls.clear();
    completeResponseCalls.clear();
    failRequestCalls.clear();
    throwSimulatedException = false;
    returnNullContext = false;
    nextContext = null;
  }
}

/// Test spy implementation of [RealtimeTrafficCollector] for verifying realtime adapters.
class SpyRealtimeTrafficCollector implements RealtimeTrafficCollector {
  @override
  int maxBodyBytes;

  @override
  int offloadThreshold;

  bool shouldCaptureDefault;
  bool Function(Uri? uri)? shouldCaptureProvider;
  bool throwOnConnection;
  bool throwOnFrame;
  bool throwOnClose;

  final List<Map<String, dynamic>> openSessionCalls = [];
  final List<Map<String, dynamic>> recordConnectionCalls = [];
  final List<Map<String, dynamic>> recordFrameCalls = [];
  final List<Map<String, dynamic>> recordCloseCalls = [];
  final List<Map<String, dynamic>> sendMessageCalls = [];

  List<Map<String, dynamic>> get closeConnectionCalls => recordCloseCalls;

  final Map<String, RealtimeSessionScope> _activeScopes = {};

  SpyRealtimeTrafficCollector({
    this.maxBodyBytes = 1024 * 1024,
    this.offloadThreshold = 64 * 1024,
    this.shouldCaptureDefault = true,
    this.shouldCaptureProvider,
    this.throwOnConnection = false,
    this.throwOnFrame = false,
    this.throwOnClose = false,
  });

  @override
  bool shouldCapture(Uri? uri) =>
      shouldCaptureProvider?.call(uri) ?? shouldCaptureDefault;

  @override
  RealtimeSessionScope openSession({
    Uri? uri,
    String? sessionId,
    Map<String, String>? headers,
    RealtimeProtocolType protocolType = RealtimeProtocolType.webSocket,
  }) {
    final effectiveId = sessionId ?? RequestId.generate();
    openSessionCalls.add({
      'sessionId': effectiveId,
      'uri': uri,
      'headers': headers,
      'protocolType': protocolType,
    });

    if (uri != null && shouldCapture(uri)) {
      try {
        recordConnection(
          sessionId: effectiveId,
          uri: uri,
          headers: headers,
          protocolType: protocolType,
        );
      } catch (_) {}
    }

    final scope = RealtimeSessionScope(
      collector: this,
      sessionId: effectiveId,
      uri: uri,
      protocolType: protocolType,
      shouldCapture: shouldCapture(uri),
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
    sendMessageCalls.add({
      'sessionId': sessionId,
      'draft': draft,
    });
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
    if (throwOnConnection) {
      throw Exception('Simulated recordConnection error');
    }
    recordConnectionCalls.add({
      'sessionId': sessionId,
      'uri': uri,
      'headers': headers,
      'protocolType': protocolType,
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
    if (throwOnFrame) {
      throw Exception('Simulated recordFrame error');
    }
    recordFrameCalls.add({
      'sessionId': sessionId,
      'direction': direction,
      'type': type,
      'payload': payload,
      'payloadSizeBytes': payloadSizeBytes,
      'timestamp': timestamp,
      'shortPreview': shortPreview,
      'shouldOffload': shouldOffload,
      'eventName': eventName,
      'preEncodedBytes': preEncodedBytes,
    });
  }

  @override
  void recordClose({
    required String sessionId,
    int? closeCode,
    String? closeReason,
  }) {
    if (throwOnClose) {
      throw Exception('Simulated recordClose error');
    }
    _activeScopes.remove(sessionId);
    recordCloseCalls.add({
      'sessionId': sessionId,
      'closeCode': closeCode,
      'closeReason': closeReason,
    });
  }

  void reset() {
    openSessionCalls.clear();
    recordConnectionCalls.clear();
    recordFrameCalls.clear();
    recordCloseCalls.clear();
    sendMessageCalls.clear();
    _activeScopes.clear();
    throwOnConnection = false;
    throwOnFrame = false;
    throwOnClose = false;
  }
}
