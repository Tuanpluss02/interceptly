# 02 — SPI Contracts (Service Provider Interfaces)

> **Scope:** Complete interface definitions for `HttpTrafficCollector`, `HttpCaptureScope`, `RealtimeTrafficCollector`, `RealtimeSessionScope`. These are the ONLY way adapters communicate with core.

---

## 2.1 `HttpTrafficCollector`

**File:** `packages/interceptly/lib/src/adapter/http_traffic_collector.dart`

```dart
abstract interface class HttpTrafficCollector {
  /// The inspector session this collector coordinates with.
  InspectorSession get session;

  /// Calculates simulated throughput delay for streaming response chunks.
  Duration delayForChunk(int chunkBytes);

  /// Whether traffic to [uri] should be captured under current session settings.
  bool shouldCapture(Uri? uri);

  /// Initiates an HTTP exchange capture, returning an [HttpCaptureScope].
  /// Throws [SimulatedNetworkException] if pre-request simulation rejects the request.
  Future<HttpCaptureScope> begin({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    String? contentType,
  });

  /// Called when request is actually sent (for streaming adapters like Chopper).
  /// Updates the scope with actual sent request details.
  void startRequest({
    required HttpRequestContext context,
    required String method,
    required Uri uri,
    required Map<String, String>? headers,
    required Uint8List? bodyBytes,
    required String? contentType,
  });

  /// Records a successful HTTP response.
  void completeResponse({
    required HttpRequestContext context,
    required int statusCode,
    required Map<String, String>? headers,
    required Uint8List? bodyBytes,
    int? responseSizeBytes,
    int? durationMs,
    String? responseContentType,
    bool? responseTruncatedAtStorage,
  });

  /// Records a failed HTTP request (transport error, connection error, or simulation failure).
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
  });
}
```

### Implementation

`DefaultHttpTrafficCollector` in same file — coordinates with `InspectorSession`, applies network simulation, computes truncation, serializes via `CapturePipeline`.

---

## 2.2 `HttpCaptureScope`

**File:** `packages/interceptly/lib/src/adapter/http_capture_scope.dart`

Thin wrapper around `HttpTrafficCollector` for a single HTTP exchange lifecycle.

```dart
class HttpCaptureScope {
  /// Whether this scope is active and can record.
  bool get isActive;

  /// Amends the request with actual sent details (e.g., after redirects in Chopper).
  void amendRequest({
    String? method,
    Uri? uri,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    String? contentType,
  });

  /// Completes the exchange successfully.
  Future<void> complete({
    required int statusCode,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    int? responseSizeBytes,
    String? contentType,
    int? durationMs,
    bool? responseTruncatedAtStorage,
  });

  /// Fails the exchange (transport error, connection error).
  void fail(
    Object error, {
    StackTrace? stackTrace,
    String? errorType,
    String? errorMessage,
    int? statusCode,
    Map<String, String>? responseHeaders,
    Uint8List? responseBodyBytes,
    int? responseSizeBytes,
    int? durationMs,
    bool? responseTruncatedAtStorage,
  });

  /// Binds a streaming response, capturing chunks up to maxBodyBytes.
  /// Automatically calls complete/fail based on stream termination.
  Stream<List<int>> bindResponseStream(
    Stream<List<int>> responseStream, {
    required int statusCode,
    Map<String, String>? headers,
    String? contentType,
  });
}
```

### Adapter Usage Pattern

```dart
// 1. Begin capture (may throw SimulatedNetworkException)
final scope = await collector.begin(
  method: options.method,
  uri: options.uri,
  headers: normalizeHeaders(options.headers),
  bodyBytes: reqBytes,
  contentType: options.contentType,
);

// 2. Store scope for response/error handling
options.extra[_scopeKey] = scope;

// 3. On response — fire and forget (must not block response)
unawaited(guardCaptureAsync(() async {
  await scope.complete(
    statusCode: response.statusCode ?? 200,
    headers: normalizeHeaders(response.headers.map),
    bodyBytes: resBytes,
    contentType: resContentType,
    durationMs: elapsedMs,
  );
}));

// 4. On error
scope.fail(
  err.error ?? err,
  errorType: err.type.name,
  errorMessage: err.message ?? err.error?.toString(),
  statusCode: response?.statusCode,
  responseHeaders: normalizeHeaders(response?.headers.map),
  responseBodyBytes: resBytes,
);
```

---

## 2.3 `RealtimeTrafficCollector`

**File:** `packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart`

```dart
abstract interface class RealtimeTrafficCollector {
  InspectorSession get session;

  /// Opens a new realtime session (WebSocket connection).
  RealtimeSessionScope openSession({
    required Uri uri,
    String? sessionId,
    Map<String, String>? headers,
  });

  /// Records a frame (text or binary) for an existing session.
  void recordFrame({
    required String sessionId,
    required FrameDirection direction,
    required FrameType type,
    required dynamic payload,
    int? sequence,
  });

  /// Records connection closure.
  void recordClose({
    required String sessionId,
    int? closeCode,
    String? closeReason,
  });
}
```

### Implementation

`DefaultRealtimeTrafficCollector` — delegates to `RealtimeStore` for session registry, applies 60fps throttling, manages ring buffer per session.

---

## 2.4 `RealtimeSessionScope`

**File:** `packages/interceptly/lib/src/adapter/realtime_session_scope.dart`

Per-connection scope handling frame throttling and ring buffer.

```dart
class RealtimeSessionScope {
  String get sessionId;
  Uri? get uri;
  bool get isClosed;

  /// Records outgoing frame (client → server).
  void send({
    required FrameType type,
    required dynamic payload,
    int? sequence,
  });

  /// Records incoming frame (server → client).
  void receive({
    required FrameType type,
    required dynamic payload,
    int? sequence,
  });

  /// Records connection close.
  void close({int? code, String? reason});

  /// Attaches a sender for replay functionality.
  void attachSender(RealtimeConnectionSender sender);
}
```

### Adapter Usage Pattern

```dart
// In InterceptlyWebSocketChannel constructor:
scope = collector.openSession(
  uri: uri ?? Uri(scheme: 'ws', host: 'unknown-socket'),
  sessionId: sessionId,
  headers: headers,
);
scope.attachSender(_WebSocketChannelSender(this));

// On outgoing frame:
sink.add(data) → scope.send(type: FrameType.text, payload: data)

// On incoming frame:
stream.listen((data) → scope.receive(type: FrameType.text, payload: data))

// On close:
sink.close() → scope.close(code: closeCode, reason: closeReason)
```

---

## 2.5 Marker Interfaces (Adapters Must Implement)

```dart
// For HTTP adapters (Dio, http, Chopper)
abstract interface class HttpCaptureAdapter {
  InspectorSession get session;
  HttpTrafficCollector get collector;
}

// For WebSocket/SSE adapters
abstract interface class RealtimeCaptureAdapter {
  InspectorSession get session;
  RealtimeTrafficCollector get collector;
}
```

---

## 2.6 Key Supporting Types

| Type | Location | Purpose |
|------|----------|---------|
| `HttpRequestContext` | `http_request_context.dart` | Request metadata passed through scope lifecycle |
| `RawCapture` | `model/raw_capture.dart` | Complete capture record sent to `WriterIsolate` |
| `BodyTruncation` | `model/body_truncation.dart` | Truncation metadata (stage, original/retained bytes) |
| `TruncationStage` | `model/body_truncation.dart` | `none` \| `preview` \| `storage` |
| `SimulatedNetworkException` | `model/network_simulation.dart` | Thrown by `begin()` when simulation rejects request |
| `FrameDirection` | `model/realtime_frame.dart` | `incoming` \| `outgoing` |
| `FrameType` | `model/realtime_frame.dart` | `text` \| `binary` |

---

## 2.7 SPI Evolution Rules

| Change | Core Version | Adapter Impact |
|--------|--------------|----------------|
| New optional param | Minor | No change needed (default values) |
| New required param | Minor | Adapters must update (minor bump) |
| Method removed/renamed | Major | Adapters must update (major bump) |
| Internal impl only | Patch | No adapter change |

**Rule:** SPI is the contract. Core version = SPI version. Adapters declare `interceptly: ^X.Y` where X.Y matches SPI version.