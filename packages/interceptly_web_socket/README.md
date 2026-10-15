# interceptly_web_socket

[![pub package](https://img.shields.io/pub/v/interceptly_web_socket.svg)](https://pub.dev/packages/interceptly_web_socket)
[![license](https://img.shields.io/github/license/Tuanpluss02/interceptly.svg)](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE)

`WebSocketChannel` adapter for the [Interceptly](https://pub.dev/packages/interceptly) realtime traffic inspector in Flutter.

`InterceptlyWebSocketChannel` wraps any `WebSocketChannel` to provide live, bidirectional frame inspection in the Interceptly inspector UI with zero jank, 60fps UI throttling, and FIFO memory management.

---

## Installation

Add both `interceptly` (the core inspector) and `interceptly_web_socket` to your project:

```bash
flutter pub add interceptly
flutter pub add interceptly_web_socket
```

---

## Quick Start

### 1. Connect Directly

Use `InterceptlyWebSocketChannel.connect`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_web_socket/interceptly_web_socket.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp(navigatorKey: navigatorKey));

  if (kDebugMode || kProfileMode) {
    Interceptly.init(
      navigatorKey: navigatorKey,
      settings: const InterceptlySettings(
        maxFramesPerSession: 1000, // Retain up to 1000 frames per connection
      ),
    );
  }

  // Connect to a WebSocket endpoint:
  final channel = InterceptlyWebSocketChannel.connect(
    Uri.parse('wss://echo.websocket.events'),
  );

  // Listen to incoming messages:
  channel.stream.listen((message) {
    print('Received from socket: $message');
  });

  // Send outgoing frames (text or binary):
  channel.sink.add('Hello Interceptly WebSocket!');
  channel.sink.add('{"action":"subscribe","channel":"crypto_prices"}');
}
```

### 2. Wrap an Existing `WebSocketChannel`

If you already manage `WebSocketChannel` creation or use custom protocols:

```dart
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:interceptly_web_socket/interceptly_web_socket.dart';

final rawChannel = WebSocketChannel.connect(uri);

final inspectedChannel = InterceptlyWebSocketChannel(
  rawChannel,
  uri: uri,
  headers: {'Authorization': 'Bearer token'},
);
```

---

## Features

- **Bidirectional Inspection**: Real-time observation of both incoming (`↓`) and outgoing (`↑`) frames.
- **Text & Binary Frames**: Inspect UTF-8 text, formatted JSON, and binary `Uint8List` frames with byte counters.
- **Connection Lifecycle**: Tracks connection establishment, active durations, and close handshake codes/reasons (e.g. `1000 Normal Closure`, `1006 Abnormal`).
- **High Frequency Flood Protection**:
  - **FIFO Ring Buffer**: Enforces `maxFramesPerSession` cap (default 1000) per connection, dropping the oldest frames when exceeded to eliminate memory bloat.
  - **60fps UI Throttling**: Batch-updates the UI viewer smoothly so 1,000+ frames/sec floods never trigger Flutter UI jank.
- **Fail-Safe**: Framing errors or inspector exceptions are non-intrusively caught and will never terminate or alter your live socket stream.

---

## Configuration Options & SPI Injection

`InterceptlyWebSocketChannel` implements `RealtimeCaptureAdapter`. By default it uses `DefaultRealtimeTrafficCollector()`, which automatically coordinates with `InspectorSession.instance`. You can also inject a custom `RealtimeTrafficCollector`:

```dart
final collector = MyCustomRealtimeTrafficCollector();

final channel = InterceptlyWebSocketChannel.connect(
  Uri.parse('wss://echo.websocket.events'),
  collector: collector,
);
```

---

## License

MIT License - see [LICENSE](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE) for details.
