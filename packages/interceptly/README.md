# Interceptly

[![pub package](https://img.shields.io/pub/v/interceptly.svg)](https://pub.dev/packages/interceptly)
[![pub points](https://img.shields.io/pub/points/interceptly.svg)](https://pub.dev/packages/interceptly)
[![license](https://img.shields.io/github/license/Tuanpluss02/interceptly.svg)](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE)

Interceptly is a high-performance, client-agnostic network & realtime inspector for Flutter. It provides real-time traffic visualization for HTTP and bidirectional WebSockets with zero UI jank and minimal memory footprint.

The core `interceptly` package contains the inspection UI overlay, background isolate processing pipeline, hybrid storage engine, and realtime stream buffer. It is completely independent of specific HTTP/WebSocket networking libraries.

---

## Install with AI agent

Paste this into your coding agent (OpenCode, Claude Code, Codex, ...):

```
Fetch and follow instructions from https://raw.githubusercontent.com/Tuanpluss02/interceptly/main/AGENTS.md
```

The agent will detect your HTTP clients, add the right packages, wire up the inspector, and verify it works.

---

## Preview

|                                            REST Inspector                                            |                                            Realtime Inspector                                            |
| :--------------------------------------------------------------------------------------------------: | :------------------------------------------------------------------------------------------------------: |
| ![REST](https://raw.githubusercontent.com/Tuanpluss02/interceptly/main/packages/interceptly/assets/images/REST_demo.gif) | ![Realtime](https://raw.githubusercontent.com/Tuanpluss02/interceptly/main/packages/interceptly/assets/images/Realtime_demo.gif) |

---

## Features

- **Client-Agnostic Core**: Zero unnecessary dependencies bundled in core. Use only the adapters your app needs.
- **High Performance**: Background isolates handle payload parsing and serialization to prevent UI frame drops.
- **Realtime WebSocket Support**: Live inspection of incoming & outgoing frames (text, JSON, binary) with 60fps throttling and per-session FIFO ring buffering.
- **Hybrid Storage**: Smart memory management that offloads large payloads to temporary files.
- **Postman-like Replay**: Built-in request editor to modify headers/body and re-send HTTP requests.
- **Network Simulation**: Global simulation profiles for Offline, Slow 3G, Fast 4G, or custom latency/bandwidth.
- **Advanced Formatters**: Specialized views for GraphQL operations, Multipart FormData, cURL generation, and Binary data.
- **Master Search**: Filter across URLs, headers, bodies, frames, and errors with instant highlight navigation.
- **Endpoint Filtering**: Synchronously filter URLs with the `shouldCapture` predicate to bypass analytics or unwanted endpoints.
- **Export**: Share or export traffic sessions as HAR, cURL commands, or Postman collections.

---

## Architecture & Satellite Adapters

To inspect network traffic, pair `interceptly` with the adapter(s) corresponding to your networking client:

| Client Library | Adapter Package | Import |
| :--- | :--- | :--- |
| [Dio](https://pub.dev/packages/dio) | [`interceptly_dio`](https://pub.dev/packages/interceptly_dio) | `import 'package:interceptly_dio/interceptly_dio.dart';` |
| [http](https://pub.dev/packages/http) | [`interceptly_http`](https://pub.dev/packages/interceptly_http) | `import 'package:interceptly_http/interceptly_http.dart';` |
| [Chopper](https://pub.dev/packages/chopper) | [`interceptly_chopper`](https://pub.dev/packages/chopper) | `import 'package:interceptly_chopper/interceptly_chopper.dart';` |
| [web_socket_channel](https://pub.dev/packages/web_socket_channel) | [`interceptly_web_socket`](https://pub.dev/packages/interceptly_web_socket) | `import 'package:interceptly_web_socket/interceptly_web_socket.dart';` |

---

## Installation

Add the core package to your `pubspec.yaml`:

```bash
flutter pub add interceptly
```

And add any network adapter(s) your application uses:

```bash
# Example: Adding Dio and WebSocket adapters
flutter pub add interceptly_dio
flutter pub add interceptly_web_socket
```

---

## Quick Start

### 1. Initialize Interceptly

Initialize Interceptly in your app startup:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';

final _navKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(navigatorKey: _navKey, home: const MyApp()));

  if (kDebugMode || kProfileMode) {
    Interceptly.init(
      navigatorKey: _navKey,
      settings: const InterceptlySettings(
        maxEntries: 1000,
        maxFramesPerSession: 1000,
      ),
      showFloatingButton: true, // Floating overlay bug button
    );
  }
}
```

### 2. Attach Adapters

#### Dio (`package:interceptly_dio`)
```dart
import 'package:dio/dio.dart';
import 'package:interceptly_dio/interceptly_dio.dart';

final dio = Dio()..interceptors.add(InterceptlyDioInterceptor());
```

#### HTTP (`package:interceptly_http`)
```dart
import 'package:http/http.dart' as http;
import 'package:interceptly_http/interceptly_http.dart';

final client = InterceptlyHttpClient(http.Client());
final response = await client.get(Uri.parse('https://api.example.com/data'));
```

#### Chopper (`package:interceptly_chopper`)
```dart
import 'package:chopper/chopper.dart';
import 'package:interceptly_chopper/interceptly_chopper.dart';

final chopper = ChopperClient(
  interceptors: [InterceptlyChopperInterceptor()],
);
```

#### WebSocket (`package:interceptly_web_socket`)
```dart
import 'package:interceptly_web_socket/interceptly_web_socket.dart';

final channel = InterceptlyWebSocketChannel.connect(
  Uri.parse('wss://echo.websocket.events'),
);

channel.stream.listen((message) {
  print('Received echo: $message');
});

channel.sink.add('Hello Interceptly!');
```

---

## Realtime API for Custom Protocols

For custom socket implementations, streaming clients, or proprietary transports, you can record realtime connections and frames directly using the `Interceptly` API:

```dart
// 1. Record connection opening
Interceptly.instance.recordRealtimeConnection(
  id: 'conn_123',
  url: 'wss://my-custom-socket.example.com',
  headers: {'User-Agent': 'FlutterApp'},
);

// 2. Record incoming or outgoing text frames
Interceptly.instance.recordRealtimeFrame(
  RealtimeFrame.text(
    id: RequestId.generate(),
    sessionId: 'conn_123',
    direction: FrameDirection.incoming,
    text: '{"event":"chat_message","body":"Hello!"}',
  ),
);

// 3. Record binary frames
Interceptly.instance.recordRealtimeFrame(
  RealtimeFrame.binary(
    id: RequestId.generate(),
    sessionId: 'conn_123',
    direction: FrameDirection.outgoing,
    bytes: uint8ListPayload,
  ),
);

// 4. Record connection closure
Interceptly.instance.closeRealtimeConnection(
  'conn_123',
  closeCode: 1000,
  closeReason: 'Normal closure',
);
```

---

## Extending Interceptly: Traffic Collectors SPI

Interceptly follows the **Bridge / SPI (Service Provider Interface)** pattern. If you use a custom networking library (such as gRPC, GraphQL, Ktor bridge, or Socket.IO), you can easily build your own adapter by implementing the contract interfaces without re-implementing timing, simulation, or storage logic:

### Custom HTTP Adapter (`HttpCaptureAdapter`)

Implement `HttpCaptureAdapter` and delegate lifecycle events to `HttpTrafficCollector`:

```dart
import 'package:interceptly/interceptly.dart';

class MyCustomHttpInterceptor implements HttpCaptureAdapter {
  MyCustomHttpInterceptor([
    HttpTrafficCollector? collector,
  ])  : collector = collector ?? DefaultHttpTrafficCollector();

  @override
  InspectorSession get session => collector.session;

  @override
  final HttpTrafficCollector collector;

  Future<void> onSend(MyCustomRequest req) async {
    // 1. Notify start of request (applies pre-request latency/offline simulation)
    final context = await collector.startRequest(
      method: req.method,
      uri: req.uri,
      headers: req.headers,
      bodyBytes: req.bodyBytes,
      contentType: req.contentType,
    );
    req.extra['interceptly_context'] = context;
  }

  Future<void> onReceive(MyCustomResponse res) async {
    final context = res.request.extra['interceptly_context'] as HttpRequestContext?;
    if (context == null) return;

    // 2. Notify completed response (applies download throttle and records capture)
    await collector.completeResponse(
      context: context,
      statusCode: res.statusCode,
      headers: res.headers,
      bodyBytes: res.bodyBytes,
      responseContentType: res.contentType,
    );
  }

  void onError(MyCustomRequest req, Object error) {
    final context = req.extra['interceptly_context'] as HttpRequestContext?;
    if (context == null) return;

    // 3. Notify request failure
    collector.failRequest(
      context: context,
      error: error,
      errorMessage: error.toString(),
    );
  }
}
```

### Custom Realtime Adapter (`RealtimeCaptureAdapter`)

For custom WebSockets, SSE streams, or MQTT/Socket.IO connections, implement `RealtimeCaptureAdapter` and delegate to `RealtimeTrafficCollector`:

```dart
import 'package:interceptly/interceptly.dart';

class MyCustomRealtimeClient implements RealtimeCaptureAdapter {
  MyCustomRealtimeClient({
    RealtimeTrafficCollector? collector,
  })  : collector = collector ?? DefaultRealtimeTrafficCollector();

  @override
  InspectorSession get session => collector.session;

  @override
  final RealtimeTrafficCollector collector;

  void onConnect(String sessionId, Uri endpoint) {
    collector.recordConnection(sessionId: sessionId, uri: endpoint);
  }

  void onMessageReceived(String sessionId, dynamic rawData) {
    collector.recordFrame(
      sessionId: sessionId,
      direction: FrameDirection.incoming,
      type: rawData is String ? FrameType.text : FrameType.binary,
      payload: rawData,
    );
  }

  void onMessageSent(String sessionId, dynamic rawData) {
    collector.recordFrame(
      sessionId: sessionId,
      direction: FrameDirection.outgoing,
      type: rawData is String ? FrameType.text : FrameType.binary,
      payload: rawData,
    );
  }

  void onDisconnect(String sessionId, int? code, String? reason) {
    collector.recordClose(
      sessionId: sessionId,
      closeCode: code,
      closeReason: reason,
    );
  }
}
```

---

## Configuration Reference

All capture parameters and limits are configured via `InterceptlySettings`:

| Parameter | Default | Description |
| :--- | :--- | :--- |
| `bodyOffloadThreshold` | `50 KB` | Body size above which payloads move from RAM to temporary files |
| `previewTruncationBytes` | `16 KB` | Inline byte budget for pending request rows awaiting a response |
| `maxBodyBytes` | `5 MB` | Hard cap before payload truncation; `<= 0` means unlimited |
| `maxUiPreviewBytes` | `2 MB` | Max bytes decoded for UI detail display; `<= 0` means unlimited |
| `maxFramesPerSession` | `1000` | Max realtime frames retained per WebSocket connection session |
| `maxQueuedEvents` | `500` | Pending capture events buffered before the background isolate is ready |
| `maxEntries` | `5000` | Maximum network requests/sessions retained in history |
| `pendingTimeout` | `45 s` | Duration after which an unfinished request is marked as timed out |
| `urlDecodeEnabled` | `true` | Decode URL percent-encodings in inspector views |
| `shouldCapture` | `null` | Optional predicate `bool Function(String url)`; returns `false` to skip capture |

> [!NOTE]
> **`shouldCapture` Execution Limits**: Evaluated synchronously on each request URL before dispatch and before queuing to background storage. The predicate must be lightweight and non-blocking. If it returns `false`, capture is completely bypassed, saving CPU and storage overhead.

---

## Network Simulation

Simulate slow or offline network conditions globally:

```dart
// Apply built-in profiles
Interceptly.instance.setNetworkSimulation(NetworkSimulationProfile.slow3G);

// Or create a custom profile
Interceptly.instance.setNetworkSimulation(
  const NetworkSimulationProfile(
    name: 'High Latency 2G',
    latencyMs: 800,
    downloadKbps: 250,
    uploadKbps: 100,
  ),
);

// Clear simulation
Interceptly.instance.clearNetworkSimulation();
```

---

## Entry-Point Configuration & Triggers

### `Interceptly.init` Configuration Table

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `navigatorKey` | `GlobalKey<NavigatorState>` | *Required* | Global navigator key used to mount overlay and push inspector screen |
| `showFloatingButton` | `bool` | `true` | Whether to display the draggable floating action button overlay |
| `fabChild` | `Widget?` | `null` | Optional custom widget rendered inside the floating action button |
| `customTrigger` | `Stream<void>?` | `null` | External event stream to trigger opening the inspector (e.g. shake detector, volume keys, gesture) |
| `settings` | `InterceptlySettings?` | Default settings | Storage thresholds, body caps, filtering predicates, and timeout durations |

> [!WARNING]
> `Interceptly.init` has no release guard: calling it in a release build ships the inspector to users. Always wrap the call in `if (kDebugMode || kProfileMode)`.

### Overlay & Navigation Triggers

- **Route Transition Observer**: Set `navigatorObservers: [Interceptly.navigatorObserver]` on your `MaterialApp` to ensure the floating overlay button always remains on top across route transitions.
- **Custom Trigger Stream**: Supply `customTrigger: shakeSensorStream` to open the inspector on device shake or hardware buttons.
- **Custom Button Icon**: Pass `fabChild: Icon(Icons.bug_report, color: Colors.amber)` to customize button appearance.
- **Programmatic Control**:
  ```dart
  // Open inspector programmatically
  Interceptly.showInspector(context);

  // Temporarily hide or show the floating action button
  Interceptly.hideFloatingButtonForSession();
  Interceptly.showFloatingButtonForSession();
  final isHidden = Interceptly.isFloatingButtonHiddenForSession;

  // Clear all recorded history
  await Interceptly.instance.clear();

  // Remove overlay and cancel trigger subscriptions
  Interceptly.detach();
  ```

---

## Storage Model

- **Small Payloads**: Kept in memory for instant responsiveness.
- **Large Payloads**: Offloaded to temporary files via a background worker isolate.
- **Lazy Loading**: Payloads are read from disk only when a record is viewed.
- **Multi-tiered Limits**: Separate caps protect memory footprint during pending requests, stored history, and UI rendering.

## Example Application

An interactive Flutter showcase application demonstrating all adapters (Dio, HTTP, Chopper, WebSocket) is provided in the [`example`](example) directory:

```bash
cd packages/interceptly/example
flutter run
```

---

## License

MIT License - see [LICENSE](LICENSE) for details.

Published by [stormx.dev](https://stormx.dev)