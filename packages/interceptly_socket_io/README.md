# interceptly_socket_io

[![pub package](https://img.shields.io/pub/v/interceptly_socket_io.svg)](https://pub.dev/packages/interceptly_socket_io)
[![license](https://img.shields.io/github/license/Tuanpluss02/interceptly.svg)](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE)

`socket_io_client` adapter for the [Interceptly](https://pub.dev/packages/interceptly) realtime traffic inspector in Flutter.

`InterceptlySocketIo` intercepts incoming (`onAny`) and outgoing (`onAnyOutgoing`) events from `package:socket_io_client`, providing live event inspection, interactive emission and replay from the inspector UI, connection lifecycle tracking, and zero-jank frame handling.

---

## Installation

Add both `interceptly` (the core inspector) and `interceptly_socket_io` to your project:

```bash
flutter pub add interceptly
flutter pub add interceptly_socket_io
```

---

## Quick Start

### 1. Initialize Interceptly

Initialize Interceptly in your application's `main()` function:

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
        maxFramesPerSession: 1000,
      ),
    );
  }
}
```

### 2. Attach to a Socket

#### Option A: Extension Method (`attachInterceptly`)

```dart
import 'package:interceptly_socket_io/interceptly_socket_io.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

final socket = io.io(
  'https://chat.example.com',
  io.OptionBuilder()
      .setTransports(['websocket'])
      .disableAutoConnect()
      .build(),
);

// Attach inspector:
final tracker = socket.attachInterceptly();

// Connect and emit events normally:
socket.connect();
socket.emit('chat_message', {'text': 'Hello Socket.IO!'});
```

#### Option B: Static Helper (`InterceptlySocketIo.attach`)

```dart
import 'package:interceptly_socket_io/interceptly_socket_io.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

final socket = io.io('https://chat.example.com');

final tracker = InterceptlySocketIo.attach(
  socket,
  headers: {'Authorization': 'Bearer <token>'},
);

socket.connect();
```

---

## Features

- **Bidirectional Event Inspection**: Real-time observation of incoming (`onAny`) and outgoing (`onAnyOutgoing`) Socket.IO events.
- **Event Badges & Payload Highlighting**: Formatted payloads with event names, JSON tree rendering, and binary byte counters.
- **Interactive Emission & Replay**: Send custom Socket.IO events directly from the Interceptly inspector UI composer, or replay captured events.
- **Lifecycle Tracking**: Monitors `connect`, `disconnect`, and `connect_error` transitions in session state.
- **Clean Detach**: `tracker.detach()` cleanly unhooks listeners without destroying socket state.
- **High Frequency Flood Protection**:
  - **FIFO Ring Buffer**: Enforces `maxFramesPerSession` cap (default 1000) per connection, dropping the oldest frames when exceeded to eliminate memory bloat.
  - **60fps UI Throttling**: Batch-updates the UI viewer smoothly so high-frequency event floods never trigger Flutter UI jank.
- **Fail-Safe**: Framing errors or inspector exceptions are non-intrusively caught via `guardCapture` and will never crash or alter your live socket stream.

---

## Configuration Options & SPI Details

Both `InterceptlySocketIo.attach` and `socket.attachInterceptly()` accept optional parameters:

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `uri` | `Uri?` | `null` | Overrides the target URI if auto-resolution from socket options and namespace is insufficient. |
| `headers` | `Map<String, String>?` | `null` | Handshake or authorization headers to record in the session inspector. |
| `sessionId` | `String?` | `null` | Explicit session identifier (UUID generated automatically when omitted). |
| `collector` | `RealtimeTrafficCollector?` | `RealtimeTrafficCollector.instance` | Injected traffic collector SPI implementation. |

### Detaching the Inspector

To stop capturing without closing or disconnecting the underlying socket:

```dart
tracker.detach();
```

---

## Complete Example

See [`example/main.dart`](example/main.dart) for a runnable standalone example.

---

## License

MIT License - see [LICENSE](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE) for details.
