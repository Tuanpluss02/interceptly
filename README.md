# Interceptly

Interceptly is a Flutter network inspector for `dio`, `http`, and `chopper`.

- Session-only storage (memory + temp file)
- Handles large payloads without blocking UI
- Built-in inspector overlay + replay tools

Current package version in this repository: `0.0.1`

---

## Requirements

- Dart: `>=3.5.0 <4.0.0`
- Flutter: `>=3.10.0`

---

## Install

```yaml
dependencies:
  interceptly: ^0.0.1
```

---

## Quick start (Dio)

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';

void main() {
  final dio = Dio()..interceptors.add(Interceptly.dioInterceptor);

  runApp(
    MaterialApp(
      home: InterceptlyOverlay(
        child: MyApp(dio: dio),
      ),
    ),
  );
}
```

---

## Integrations

### Dio

```dart
final dio = Dio()..interceptors.add(Interceptly.dioInterceptor);

// Or explicit constructor
// dio.interceptors.add(InterceptlyDioInterceptor());
```

### HTTP (`package:http`)

```dart
import 'package:http/http.dart' as http;

final client = Interceptly.wrapHttpClient(http.Client());
// or InterceptlyHttpClient(http.Client())

final res = await client.get(Uri.parse('https://api.example.com/users'));
```

### Chopper

```dart
import 'package:chopper/chopper.dart';

final chopper = ChopperClient(
  interceptors: [
    InterceptlyChopperInterceptor(),
  ],
  // ... your converter/services
);
```

---

## Open inspector

```dart
// Always works with context
Interceptly.showInspector(context);

// Works without context if navigatorKey was passed to InterceptlyOverlay
Interceptly.showInspector();
```

---

## Overlay triggers

Configure triggers via `InterceptlyConfig`:

```dart
InterceptlyOverlay(
  config: InterceptlyConfig(
    triggers: {
      InspectorTrigger.floatingButton, // default
      InspectorTrigger.shake,
      InspectorTrigger.longPress,
    },
    shakeThreshold: 15.0,
    shakeMinInterval: Duration(milliseconds: 1000),
    longPressDuration: Duration(milliseconds: 800),
    fabChild: Icon(Icons.network_check, color: Colors.white),
  ),
  child: ...,
)
```

You can also open via any custom stream:

```dart
InterceptlyOverlay(
  customTrigger: myTriggerStream,
  child: ...,
)
```

---

## Features

- Capture request lifecycle early (pending shown immediately, then updated on response/error)
- Detail pages for request/response/error/message tabs
- URL decode toggle in UI
- Search inside details with match navigation
- Export HAR and copy as cURL
- Replay tools in detail screen:
  - `Retry Request`
  - `Duplicate & Edit` (Postman-like editor with `Params / Headers / Body`)
- JSON editors in replay screen:
  - Header JSON editor
  - Body JSON editor
  - JSON format + validation + syntax highlight
- Better body rendering:
  - `application/x-www-form-urlencoded` formatter
  - `multipart/form-data` summary formatter
  - GraphQL payload formatter
  - Binary preview metadata (image/pdf/protobuf/msgpack fallback)
  - Content-Encoding indicator (`gzip` / `br` decode status)

---

## Network simulation (DevTools-like)

Interceptly supports runtime network simulation profiles:

- `No throttling`
- `Offline`
- `Slow 3G`
- `Fast 3G`
- `4G`
- `Wi‑Fi`
- `Custom` (latency/upload/download sliders in settings)

Programmatic control:

```dart
Interceptly.instance.setNetworkSimulation(NetworkSimulationProfile.slow3G);

Interceptly.instance.setNetworkSimulation(
  const NetworkSimulationProfile(
    name: 'Custom',
    offline: false,
    latencyMs: 250,
    downloadKbps: 1200,
    uploadKbps: 600,
  ),
);

Interceptly.instance.clearNetworkSimulation();
```

> Note: Simulation only applies to requests going through Interceptly wrappers/interceptors.

---

## Capture control

```dart
Interceptly.instance.disable(); // stop recording
Interceptly.instance.enable();  // resume
```

---

## Custom session

```dart
final session = InspectorSession(
  settings: const InterceptlySettings(
    bodyOffloadThreshold: 100 * 1024,
    maxEntries: 1000,
  ),
);

final dio = Dio()..interceptors.add(InterceptlyDioInterceptor(session));

runApp(
  MaterialApp(
    home: InterceptlyOverlay(
      session: session,
      child: MyApp(dio: dio),
    ),
  ),
);
```

---

## Storage model

```text
Body < bodyOffloadThreshold  -> kept inline in memory
Body >= bodyOffloadThreshold -> offloaded to temp file (offset/length in RAM)
List view                    -> reads memory index only
Detail view                  -> lazy loads only selected record
```

Large-body serialization/writes are done via a background isolate.

---

## InterceptlySettings

| Parameter | Default | Description |
|---|---|---|
| `bodyOffloadThreshold` | `50 * 1024` | Body size threshold for file offload |
| `previewTruncationBytes` | `16 * 1024` | Max bytes kept when body is truncated |
| `maxBodyBytes` | `2 * 1024 * 1024` | Hard cap before truncation |
| `maxQueuedEvents` | `500` | Max pending write queue events |
| `maxEntries` | `5000` | Max items kept in memory index |
| `urlDecodeEnabled` | `true` | Initial URL decode state in UI |

---

## Router / navigatorKey setup

If you use `MaterialApp.router` / GoRouter, pass your app navigator key to the overlay so `Interceptly.showInspector()` can work without context.

```dart
final navigatorKey = GlobalKey<NavigatorState>();

MaterialApp.router(
  routerConfig: router,
  builder: (context, child) {
    return InterceptlyOverlay(
      navigatorKey: navigatorKey,
      child: child ?? const SizedBox(),
    );
  },
)
```

---

## Notes

- The floating trigger button is draggable.
- Session data is in-memory + temp file only (no DB).
- For runnable integration examples, check the `example/` folder.
