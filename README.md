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
- **Flexible Triggers**: Support for Shake, Long Press, Floating Button, or Custom Streams.

---

## Install

Add the following to your `pubspec.yaml`:

```yaml
dependencies:
  interceptly: ^1.1.3
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
    Interceptly.attach(navigatorKey: _navKey);
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

### InterceptlySettings

| Parameter              | Default | Description                              |
| :--------------------- | :------ | :--------------------------------------- |
| `bodyOffloadThreshold` | `50 KB` | Threshold to move body to temp file      |
| `maxEntries`           | `5000`  | Maximum requests kept in history         |
| `maxBodyBytes`         | `2 MB`  | Hard cap for body size before truncation |

### UI Triggers
```dart
Interceptly.attach(
  navigatorKey: _navKey,
  config: InterceptlyConfig(
    triggers: {
      InspectorTrigger.floatingButton,
      InspectorTrigger.shake,
      InspectorTrigger.longPress,
    },
  ),
);
```

---

## Navigator Setup (MaterialApp.router / GoRouter)

Pass the same navigator key you registered on the router:

```dart
final _navKey = GlobalKey<NavigatorState>();

GoRouter(navigatorKey: _navKey, routes: [...]);

// After runApp:
if (kDebugMode || kProfileMode) {
  Interceptly.attach(navigatorKey: _navKey);
}
```

---

## Storage Model

- **Small Payloads**: Kept in memory for instant access.
- **Large Payloads**: Written to temporary files via background isolates.
- **Lazy Loading**: Data is only read from disk when a record is selected.

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---
Published by [stormx.dev](https://stormx.dev)