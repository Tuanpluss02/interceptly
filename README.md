# Interceptly Monorepo

[![license](https://img.shields.io/github/license/Tuanpluss02/interceptly.svg)](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE)
[![melos](https://img.shields.io/badge/maintained%20with-melos-f700ff.svg)](https://github.com/invertase/melos)

High-performance, client-agnostic network & realtime traffic inspector for Flutter applications. Interceptly provides real-time visualization of HTTP requests, responses, and bidirectional WebSocket frames with zero UI jank and minimal memory footprint.

---

## Install with AI agent

Paste this into your coding agent (OpenCode, Claude Code, Codex, ...):

```
Fetch and follow instructions from https://raw.githubusercontent.com/Tuanpluss02/interceptly/main/AGENTS.md
```

The agent will detect your HTTP clients, add the right packages, wire up the inspector, and verify it works.

---

## Architecture Overview

Interceptly is organized as a modular monorepo managed with [Melos](https://melos.invertase.dev/). The core inspection engine and UI are completely client-agnostic, while lightweight satellite adapter packages provide seamless integration with popular networking libraries.

```
├── packages/
│   ├── interceptly              # Core engine, UI overlay, isolate processing & storage
│   ├── interceptly_dio          # Adapter for Dio (InterceptlyDioInterceptor)
│   ├── interceptly_http         # Adapter for package:http (InterceptlyHttpClient)
│   ├── interceptly_chopper      # Adapter for Chopper (InterceptlyChopperInterceptor)
│   └── interceptly_web_socket   # Adapter for WebSocketChannel (InterceptlyWebSocketChannel)
└── packages/interceptly/example # Interactive Flutter showcase app
```

### Packages

| Package | Version | Description |
| :--- | :--- | :--- |
| [`interceptly`](packages/interceptly) | `^2.1.0` | **Core package**: Flutter UI inspector overlay, background isolate pipeline, hybrid disk/RAM storage, throttling buffer, and realtime inspection. |
| [`interceptly_dio`](packages/interceptly_dio) | `^1.0.0` | **Dio Adapter**: Non-intrusive `Interceptor` recording HTTP requests, responses, and errors. |
| [`interceptly_http`](packages/interceptly_http) | `^1.0.0` | **HTTP Adapter**: Stream-teeing `http.Client` wrapper preserving single-subscription response streams. |
| [`interceptly_chopper`](packages/interceptly_chopper) | `^1.0.0` | **Chopper Adapter**: `ResponseInterceptor` and `RequestInterceptor` capturing Chopper network traffic. |
| [`interceptly_web_socket`](packages/interceptly_web_socket) | `^1.0.0` | **WebSocket Adapter**: `WebSocketChannel` wrapper capturing bidirectional text/binary frames in real time. |

---

## Quick Start

### 1. Install Packages

Add the core package and the adapter(s) corresponding to your network client:

```bash
flutter pub add interceptly

# Add the adapter(s) you need:
flutter pub add interceptly_dio
flutter pub add interceptly_http
flutter pub add interceptly_chopper
flutter pub add interceptly_web_socket
```

For local monorepo development, path dependencies can also be used:

```yaml
dependencies:
  interceptly:
    path: packages/interceptly
  interceptly_dio:
    path: packages/interceptly_dio
```

### 2. Initialize Interceptly

Initialize Interceptly in your app startup:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp(navigatorKey: navigatorKey));

  if (kDebugMode || kProfileMode) {
    Interceptly.init(
      navigatorKey: navigatorKey,
      settings: const InterceptlySettings(
        maxEntries: 1000,
        maxFramesPerSession: 1000,
      ),
    );
  }
}
```

### 3. Attach Network Adapters

#### Dio
```dart
import 'package:dio/dio.dart';
import 'package:interceptly_dio/interceptly_dio.dart';

final dio = Dio()..interceptors.add(InterceptlyDioInterceptor());
```

#### HTTP (`package:http`)
```dart
import 'package:http/http.dart' as http;
import 'package:interceptly_http/interceptly_http.dart';

final client = InterceptlyHttpClient.wrap(http.Client());
```

#### Chopper
```dart
import 'package:chopper/chopper.dart';
import 'package:interceptly_chopper/interceptly_chopper.dart';

final chopper = ChopperClient(
  interceptors: [InterceptlyChopperInterceptor()],
);
```

#### WebSocket (`package:web_socket_channel`)
```dart
import 'package:interceptly_web_socket/interceptly_web_socket.dart';

final channel = InterceptlyWebSocketChannel.connect(
  Uri.parse('wss://echo.websocket.events'),
);

// Listen and send frames normally — Interceptly captures them live!
channel.stream.listen((message) => print('Received: $message'));
channel.sink.add('Hello Interceptly!');
```

---

## Entry-Point Configuration & Triggers

### `Interceptly.init` Parameters

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `navigatorKey` | `GlobalKey<NavigatorState>` | *Required* | Global navigator key used to mount overlay and push inspector screen |
| `showFloatingButton` | `bool` | `true` | Whether to display the draggable floating action button overlay |
| `fabChild` | `Widget?` | `null` | Optional custom widget rendered inside the floating action button |
| `customTrigger` | `Stream<void>?` | `null` | Stream triggering inspector opening (e.g. shake detector, volume keys, gesture) |
| `settings` | `InterceptlySettings?` | Default settings | Storage thresholds, body caps, filtering predicates, and timeout durations |

> [!WARNING]
> `Interceptly.init` has no release guard: calling it in a release build ships the inspector to users. Always wrap the call in `if (kDebugMode || kProfileMode)`.

### Overlay & Navigation Triggers

- **Route Transition Observer**: Set `navigatorObservers: [Interceptly.navigatorObserver]` on `MaterialApp` to ensure the floating overlay button always remains on top across route changes.
- **Custom Trigger Stream**: Supply `customTrigger: shakeSensorStream` to open the inspector on device shake or hardware buttons.
- **Custom Button Icon**: Pass `fabChild: Icon(Icons.bug_report, color: Colors.amber)` to customize button appearance.
- **Programmatic Control**:
  ```dart
  Interceptly.showInspector(context); // Open inspector view directly
  Interceptly.hideFloatingButtonForSession(); // Hide floating button for session
  Interceptly.showFloatingButtonForSession(); // Restore floating button
  final isHidden = Interceptly.isFloatingButtonHiddenForSession;
  Interceptly.detach(); // Remove overlay and cancel subscriptions
  ```

### Filtering Requests with `shouldCapture`

You can pass a custom filter predicate to `InterceptlySettings.shouldCapture`:

```dart
InterceptlySettings(
  shouldCapture: (url) {
    // Return false to skip capture entirely
    return !url.contains('/health-check') && !url.contains('/analytics');
  },
)
```

> [!NOTE]
> `shouldCapture` is executed synchronously on every outbound request before dispatch. It must be fast, non-blocking, and lightweight. Requests returning `false` are completely ignored and consume zero memory or disk storage.

---

## Architecture: Bridge Pattern & Traffic Collectors SPI

All satellite adapters in Interceptly follow a unified **Bridge & SPI** pattern, delegating coordination to core collectors:

- **`HttpTrafficCollector` & `DefaultHttpTrafficCollector`**: Handles request lifecycle coordination, timing & duration calculation, network simulation (latency, bandwidth throttling, offline exceptions), request body/response body serialization to isolates, and session persistence.
- **`RealtimeTrafficCollector` & `DefaultRealtimeTrafficCollector`**: Handles WebSocket/SSE connection tracking, frame type conversion (text vs. binary), payload serialization, and 60fps throttled ring buffer storage.
- **Marker Contracts**: Satellite adapters implement `HttpCaptureAdapter` or `RealtimeCaptureAdapter` to guarantee access to their underlying collector and session.

This design decouples application networking frameworks from Interceptly's internal storage and simulation engines, making it trivial to create custom adapters for any protocol (gRPC, GraphQL, MQTT, Socket.IO) without duplicating code or leaking exceptions.

---

## Monorepo Development & Contribution

This repository uses [Melos](https://pub.dev/packages/melos) to manage dependencies and multi-package scripts.

### Prerequisites

- Flutter SDK `>=3.10.0`
- Dart SDK `>=3.5.0 <4.0.0`
- Melos CLI (`dart pub global activate melos`)

### Common Commands

```bash
# Bootstrap all packages and link local path dependencies
melos bootstrap

# Run static analysis across all packages and the example
melos run analyze

# Run all test suites across all packages
melos run test

# Clean build artifacts across all packages
melos run clean
```

---

## Example Application

An interactive Flutter showcase application demonstrating all adapters (Dio, HTTP, Chopper, WebSocket) is provided in [`packages/interceptly/example`](packages/interceptly/example):

```bash
cd packages/interceptly/example
flutter run
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
