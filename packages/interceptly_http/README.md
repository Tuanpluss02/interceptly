# interceptly_http

[![pub package](https://img.shields.io/pub/v/interceptly_http.svg)](https://pub.dev/packages/interceptly_http)
[![license](https://img.shields.io/github/license/Tuanpluss02/interceptly.svg)](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE)

Standard `http.Client` wrapper adapter for the [Interceptly](https://pub.dev/packages/interceptly) network inspector in Flutter.

`InterceptlyHttpClient` intercepts all requests sent through Dart's standard `package:http`, accurately capturing headers, request bodies, streamed responses, and error conditions while preserving single-subscription stream integrity.

---

## Installation

Add both `interceptly` (the core inspector) and `interceptly_http` to your `pubspec.yaml`:

```bash
flutter pub add interceptly
flutter pub add interceptly_http
```

---

## Quick Start

Wrap your standard `http.Client`:

```dart
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_http/interceptly_http.dart';

final navigatorKey = GlobalKey<NavigatorState>();

// Wrap any http.Client instance:
final client = InterceptlyHttpClient.wrap(http.Client());

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp(navigatorKey: navigatorKey));

  if (kDebugMode || kProfileMode) {
    Interceptly.init(navigatorKey: navigatorKey);
  }

  // Use the client normally:
  final response = await client.get(Uri.parse('https://api.example.com/data'));
  print('Status: ${response.statusCode}');
}
```

---

## Features

- **Stream Teeing**: Seamlessly splits `StreamedResponse.stream` into dual broadcast paths so your consuming code receives the exact untouched response bytes while Interceptly records traffic.
- **Cancellation & Error Safe**: Stream cancellations or socket exceptions are handled cleanly without memory leaks or hanging futures.
- **Zero Configuration**: Drop-in replacement for any `http.BaseClient` or `http.Client`.
- **Global Network Simulation**: Respects latency, bandwidth throttling, and offline profiles defined in Interceptly.

---

## Custom Configuration

You can also instantiate `InterceptlyHttpClient` directly with a custom inner client or custom controller:

```dart
final client = InterceptlyHttpClient(
  http.Client(),
  interceptly: Interceptly.instance,
);
```

---

## License

MIT License - see [LICENSE](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE) for details.
