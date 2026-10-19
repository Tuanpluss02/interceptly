# interceptly_socket_io

[![pub package](https://img.shields.io/pub/v/interceptly_socket_io.svg)](https://pub.dev/packages/interceptly_socket_io)
[![license](https://img.shields.io/github/license/Tuanpluss02/interceptly.svg)](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE)

`socket_io_client` adapter for the [Interceptly](https://pub.dev/packages/interceptly) realtime traffic inspector in Flutter.

`InterceptlySocketIo` intercepts incoming (`onAny`) and outgoing (`onAnyOutgoing`) events from `package:socket_io_client`, providing live event inspection, interactive emission from the inspector UI, connection lifecycle tracking, and zero-jank frame handling.

---

## Installation

Add both `interceptly` (the core inspector) and `interceptly_socket_io` to your project:

```bash
flutter pub add interceptly
flutter pub add interceptly_socket_io
```

---

## Quick Start

### 1. Attach to a Socket

Use `InterceptlySocketIo.attach` or the extension method `socket.attachInterceptly()`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_socket_io/interceptly_socket_io.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp(navigatorKey: navigatorKey));

  if (kDebugMode || kProfileMode) {
    Interceptly.init(navigatorKey: navigatorKey);
  }

  // Create your Socket.IO client instance:
  final socket = io.io('https://chat.example.com', <String, dynamic>{
    'transports': ['websocket'],
    'autoConnect': false,
  });

  // Attach Interceptly inspector:
  socket.attachInterceptly();

  // Connect socket:
  socket.connect();
}
```

---

## Features

- **Bidirectional Event Inspection**: Real-time observation of incoming (`onAny`) and outgoing (`onAnyOutgoing`) Socket.IO events.
- **Event Badges & Payload Highlighting**: Formatted payloads with event names, JSON tree rendering, and binary byte counters.
- **Interactive Emission**: Send custom Socket.IO events directly from the Interceptly inspector UI composer.
- **Lifecycle Tracking**: Monitors `connect`, `disconnect`, and `connect_error` transitions in session state.
- **Clean Detach**: `tracker.detach()` cleanly unhooks listeners without destroying socket state.
- **Fail-Safe**: Framing errors or inspector exceptions are non-intrusively caught via `guardCapture`.

---

## License

MIT License - see [LICENSE](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE) for details.
