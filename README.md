# Interceptly Monorepo

[![license](https://img.shields.io/github/license/Tuanpluss02/interceptly.svg)](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE)
[![melos](https://img.shields.io/badge/maintained%20with-melos-f700ff.svg)](https://github.com/invertase/melos)

High-performance, client-agnostic network & realtime traffic inspector for Flutter applications. Interceptly provides real-time visualization of HTTP requests, responses, and bidirectional WebSocket frames with zero UI jank and minimal memory footprint.

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
| [`interceptly`](packages/interceptly) | `^2.0.3` | **Core package**: Flutter UI inspector overlay, background isolate pipeline, hybrid disk/RAM storage, throttling buffer, and realtime inspection. |
| [`interceptly_dio`](packages/interceptly_dio) | `^1.0.0` | **Dio Adapter**: Non-intrusive `Interceptor` recording HTTP requests, responses, and errors. |
| [`interceptly_http`](packages/interceptly_http) | `^1.0.0` | **HTTP Adapter**: Stream-teeing `http.Client` wrapper preserving single-subscription response streams. |
| [`interceptly_chopper`](packages/interceptly_chopper) | `^1.0.0` | **Chopper Adapter**: `ResponseInterceptor` and `RequestInterceptor` capturing Chopper network traffic. |
| [`interceptly_web_socket`](packages/interceptly_web_socket) | `^1.0.0` | **WebSocket Adapter**: `WebSocketChannel` wrapper capturing bidirectional text/binary frames in real time. |

---

## Quick Start

### 1. Install Packages

Add the core package and the adapter(s) corresponding to your network client:

```yaml
dependencies:
  flutter:
    sdk: flutter
  interceptly: ^2.0.3

  # Choose one or more adapters:
  interceptly_dio: ^1.0.0
  interceptly_http: ^1.0.0
  interceptly_chopper: ^1.0.0
  interceptly_web_socket: ^1.0.0
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
        maxFramesPerSession: 500,
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

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
