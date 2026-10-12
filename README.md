# Interceptly

[![pub package](https://img.shields.io/pub/v/interceptly.svg)](https://pub.dev/packages/interceptly)
[![pub points](https://img.shields.io/pub/points/interceptly.svg)](https://pub.dev/packages/interceptly)
[![license](https://img.shields.io/github/license/Tuanpluss02/interceptly.svg)](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE)

Interceptly is a high-performance network inspector for Flutter. It provides real-time traffic visualization for Dio, Http, and Chopper with minimal impact on UI performance.

---

## Preview

|                                             Inspector Overview                                              |                                                 Request Details                                                  |                                                 Replay Tool                                                 |
| :---------------------------------------------------------------------------------------------------------: | :--------------------------------------------------------------------------------------------------------------: | :---------------------------------------------------------------------------------------------------------: |
| ![Overview](https://raw.githubusercontent.com/Tuanpluss02/interceptly/main/assets/images/overview_demo.gif) | ![Details](https://raw.githubusercontent.com/Tuanpluss02/interceptly/main/assets/images/request_detail_demo.gif) | ![Replay](https://raw.githubusercontent.com/Tuanpluss02/interceptly/main/assets/images/relay_tool_demo.gif) |

---

## Features

- **High Performance**: Background isolates handle all serialization logic to prevent UI jank.
- **Hybrid Storage**: Smart memory management that offloads large payloads to temporary files.
- **Postman-like Replay**: Built-in request editor to modify headers/body and re-send requests.
- **Network Simulation**: Global profiles for Offline, 3G, 4G, or custom latency/bandwidth.
- **Advanced Formatters**: Specialized views for GraphQL, Multipart, cURL, and Binary data.
- **Master Search**: One query across URLs, headers, bodies, and errors with match navigation.
- **Safe by Default**: Sensitive headers are redacted before storage; `shouldCapture` filters URLs.
- **Export**: Share or export records as HAR, cURL, or Postman collections.
- **Flexible Triggers**: Floating bug button or custom streams.

---

## Install

Run the following command in your terminal:

```bash
flutter pub add interceptly
```

---

## Quick Start (Dio)

```dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';

final _navKey = GlobalKey<NavigatorState>();
final _dio = Dio()..interceptors.add(InterceptlyDioInterceptor());

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(navigatorKey: _navKey, home: MyApp(dio: _dio)));

  if (kDebugMode || kProfileMode) {
    Interceptly.init(navigatorKey: _navKey);
  }
}
```

---

## Integrations

### HTTP (package:http)
```dart
import 'package:http/http.dart' as http;

final client = InterceptlyHttpClient.wrap(http.Client());
final res = await client.get(Uri.parse('https://api.example.com/data'));
```

### Chopper
```dart
final chopper = ChopperClient(
  interceptors: [InterceptlyChopperInterceptor()],
);
```

---

## Network Simulation

Simulate various network conditions globally for all intercepted requests:

```dart
// Apply built-in profiles
Interceptly.instance.setNetworkSimulation(NetworkSimulationProfile.slow3G);

// Custom profile definition
Interceptly.instance.setNetworkSimulation(
  const NetworkSimulationProfile(
    name: 'Custom Profile',
    latencyMs: 500,
    downloadKbps: 1000,
    uploadKbps: 500,
  ),
);
```

---

## Configuration

All capture behavior is configured through a single `InterceptlySettings` object. Pass it to `Interceptly.init` once at startup:

```dart
Interceptly.init(
  navigatorKey: _navKey,
  settings: const InterceptlySettings(
    // Security & Filtering
    redactedHeaders: {'authorization', 'cookie', 'set-cookie', 'x-api-key'},
    shouldCapture: _skipAnalytics,
    // Storage & Retention
    maxBodyBytes: 1024 * 1024, // 1 MB
    maxEntries: 1000,
  ),
  showFloatingButton: true, // false to hide FAB
  customTrigger: myTriggerStream, // optional custom stream trigger
);

bool _skipAnalytics(String url) => !url.contains('/analytics');
```

### InterceptlySettings Reference

| Parameter                 | Default        | Description                                                     |
| :------------------------ | :------------- | :-------------------------------------------------------------- |
| `bodyOffloadThreshold`    | `50 KB`        | Body size above which payloads move to a temp file               |
| `previewTruncationBytes`  | `16 KB`        | Inline byte budget for pending request rows awaiting a response  |
| `maxBodyBytes`            | `5 MB`         | Hard cap before body truncation; `<= 0` means unlimited          |
| `maxUiPreviewBytes`       | `2 MB`         | Max bytes decoded for the detail preview; `<= 0` means unlimited |
| `maxQueuedEvents`         | `500`          | Pending capture events buffered before the isolate is ready      |
| `maxEntries`              | `5000`         | Maximum requests kept in history                                 |
| `pendingTimeout`          | `45 s`         | Marks an unfinished pending request as timed out                  |
| `urlDecodeEnabled`        | `true`         | Decode URL encodings in the UI                                   |
| `redactedHeaders`         | 4 auth headers | Header names replaced with `[REDACTED]` (case-insensitive)       |
| `shouldCapture`           | `null`         | `bool Function(String url)` predicate; return `false` to skip    |

`shouldCapture` holds a closure and is evaluated on the main isolate, so it never crosses an isolate boundary.

### FAB Session Control

```dart
Interceptly.hideFloatingButtonForSession(); // stays hidden until app restart
Interceptly.showFloatingButtonForSession();
Interceptly.isFloatingButtonHiddenForSession;
```

---

## Navigator Setup (MaterialApp.router / GoRouter)

Pass the same navigator key you registered on the router:

```dart
final _navKey = GlobalKey<NavigatorState>();

GoRouter(navigatorKey: _navKey, routes: [...]);

// After runApp:
if (kDebugMode || kProfileMode) {
  Interceptly.init(navigatorKey: _navKey);
}
```

---

## Storage Model

- **Small Payloads**: Kept in memory for instant access.
- **Large Payloads**: Written to temporary files via background isolates.
- **Lazy Loading**: Data is only read from disk when a record is selected.
- **Three-tier size limits**: `previewTruncationBytes` caps pending rows in RAM, `maxBodyBytes` caps what is stored, and `maxUiPreviewBytes` caps what gets decoded for the detail view.

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---
Published by [stormx.dev](https://stormx.dev)