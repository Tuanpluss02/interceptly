# NetSpecter

A Flutter network inspector — zero heavy dependencies, session-only storage, no lag even with thousands of large requests.

Tested with: **Flutter 3.22+ / Dart 3.5+**

---

## How it works

```
Body < 50 KB   →  Kept inline in RAM (Uint8List)
Body ≥ 50 KB   →  Offloaded to temp file — only (offset, length) kept in RAM
List view      →  Reads MemoryIndex only — zero file I/O on scroll
Detail view    →  RandomAccessFile.setPosition(offset) — reads only the needed region
Session end    →  Memory + temp file cleared; OS cleans up on crash
```

Large-body serialisation runs in a dedicated `dart:isolate` — the main thread is never blocked.

---

## Features

- Capture `dio` requests/responses/errors — zero-copy via `TransferableTypedData`
- Capture `dart:http` requests via `NetSpecterHttpClient`
- Session-only storage — no database, no leftover files, no `build_runner`
- **Multiple open triggers:** floating button, shake, long-press, or any custom stream
- **Open programmatically** from anywhere — `NetSpecter.showInspector()`
- **Enable/disable capture** at runtime without touching the interceptor
- Filter by method, status code, host, and text query — pure in-memory, instant
- Body viewer with **JSON pretty-print**, **URL-decode**, and copy button
- Export to HAR or copy as cURL

---

## Getting Started

```yaml
dependencies:
  netspecter: ^0.0.1
```

---

## Quick Start

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:netspecter/netspecter.dart';

void main() {
  final dio = Dio()..interceptors.add(NetSpecterDioInterceptor());

  runApp(
    MaterialApp(
      home: NetSpecterOverlay(child: MyApp(dio: dio)),
    ),
  );
}
```

`NetSpecterOverlay` uses `InspectorSession.instance` internally — no manual init needed.

---

## Triggers

Control how the inspector is opened via `NetSpecterConfig`.

### Built-in triggers

```dart
NetSpecterOverlay(
  config: NetSpecterConfig(
    triggers: {
      InspectorTrigger.floatingButton, // draggable red bug button (default)
      InspectorTrigger.shake,          // shake the device
      InspectorTrigger.longPress,      // long-press any blank area
    },

    // Shake tuning
    shakeThreshold: 15.0,                          // m/s², default 15
    shakeMinInterval: Duration(milliseconds: 1000), // cooldown, default 1s

    // Long-press tuning
    longPressDuration: Duration(milliseconds: 800), // default 800ms

    // Custom floating button icon (optional)
    fabChild: Icon(Icons.network_check, color: Colors.white),
  ),
  child: ...,
)
```

### Custom trigger stream

Wire any external event source — local notifications, remote flags, custom gestures:

```dart
final _triggerController = StreamController<void>.broadcast();

// Example: local notification tap
notificationsPlugin.onDidReceiveNotificationResponse = (_) {
  _triggerController.add(null);
};

NetSpecterOverlay(
  customTrigger: _triggerController.stream,
  child: ...,
)
```

---

## Open inspector programmatically

```dart
// With a BuildContext (always works)
NetSpecter.showInspector(context);

// Without context — requires navigatorKey to be registered (see GoRouter section)
NetSpecter.showInspector();
```

---

## Enable / Disable capture

Pause capturing without removing the interceptor — useful for sensitive screens:

```dart
// On entering a payment screen
NetSpecter.instance.disable();

// On leaving
NetSpecter.instance.enable();
```

The interceptor keeps running; data is silently dropped while disabled.

---

## `MaterialApp.router` / GoRouter

Your app **already owns** a `GlobalKey<NavigatorState>`. Pass it into `NetSpecterOverlay` — the package uses it for navigation without asking you to change anything else.

```dart
import 'package:go_router/go_router.dart';
import 'package:netspecter/netspecter.dart';

// 1. Your app owns and controls this key (as always):
final _navigatorKey = GlobalKey<NavigatorState>();

final _router = GoRouter(
  navigatorKey: _navigatorKey, // ← your key, your router
  routes: [ /* ... */ ],
);

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      builder: (context, child) {
        return NetSpecterOverlay(
          navigatorKey: _navigatorKey, // ← pass your key here
          child: child ?? const SizedBox(),
        );
      },
    );
  }
}
```

Once the key is passed, `NetSpecter.showInspector()` works without a `BuildContext`.

---

## `dart:http` integration

```dart
import 'package:http/http.dart' as http;
import 'package:netspecter/netspecter.dart';

// Option A — factory helper
final client = NetSpecter.wrapHttpClient(http.Client());

// Option B — direct constructor
final client = NetSpecterHttpClient(http.Client());

final response = await client.get(Uri.parse('https://api.example.com/data'));
```

---

## Custom session

Useful for tests or running multiple isolated inspectors side by side:

```dart
final session = InspectorSession(
  settings: NetSpecterSettings(
    bodyOffloadThreshold: 100 * 1024, // 100 KB before offloading to file
    maxEntries: 1000,
  ),
);

final dio = Dio()..interceptors.add(NetSpecterDioInterceptor(session));

runApp(
  MaterialApp(
    home: NetSpecterOverlay(session: session, child: MyApp(dio: dio)),
  ),
);
```

---

## Debug-only usage (recommended)

```dart
import 'package:flutter/foundation.dart';

void main() {
  final dio = Dio();
  if (kDebugMode) {
    dio.interceptors.add(NetSpecterDioInterceptor());
  }
  runApp(MyApp(dio: dio));
}
```

---

## Integration matrix

| Setup | Placement | Pass `navigatorKey` to overlay? |
|---|---|---|
| `MaterialApp` (plain) | `home:` or inside `builder:` | Not required — falls back to context |
| `MaterialApp.router` + GoRouter | `builder:` callback | **Yes** — pass your existing GoRouter key |
| `MaterialApp` with custom key | inside `MaterialApp` | **Yes** — pass your existing key |

---

## Settings

| Parameter | Default | Description |
|---|---|---|
| `bodyOffloadThreshold` | 50 KB | Bodies above this are written to a temp file; below stays in RAM |
| `previewTruncationBytes` | 16 KB | Max bytes shown in body preview before `[truncated]` suffix |
| `maxBodyBytes` | 2 MB | Hard cap — bodies larger than this are truncated before storage |
| `maxQueuedEvents` | 500 | Write queue depth; oldest unprocessed entry is dropped when full |
| `maxEntries` | 5 000 | Max entries in the memory index; oldest is evicted when exceeded |

---

## Body viewer

The detail screen automatically detects body format and offers display modes:

| Content-Type | Default view | Available toggles |
|---|---|---|
| `application/json` | Pretty (indented) | Raw · Pretty |
| `application/x-www-form-urlencoded` | Decoded (key/value table) | Raw · Decoded |
| Binary (`image/*`, `application/octet-stream`, …) | `[binary: N bytes]` | — |
| Other text | Raw | — |

A **Copy** button on each body section copies the currently displayed text.

---

## Notes

- The floating button snaps to the nearest screen edge when released.
- Session data (memory + temp file) is cleared on `session.clear()` or `session.dispose()`. If the app crashes, the temp file sits in `getTemporaryDirectory()` and is cleaned up by the OS.
- For a complete runnable example, see the `example/` folder.
