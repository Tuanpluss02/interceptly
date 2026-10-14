# interceptly_dio

[![pub package](https://img.shields.io/pub/v/interceptly_dio.svg)](https://pub.dev/packages/interceptly_dio)
[![license](https://img.shields.io/github/license/Tuanpluss02/interceptly.svg)](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE)

Dio HTTP interceptor adapter for the [Interceptly](https://pub.dev/packages/interceptly) network inspector in Flutter.

`InterceptlyDioInterceptor` seamlessly captures outgoing HTTP requests, incoming responses, error details, and multipart data without impacting UI performance or interfering with your application logic.

---

## Installation

Add both `interceptly` (the core inspector) and `interceptly_dio` to your project:

```bash
flutter pub add interceptly
flutter pub add interceptly_dio
```

---

## Quick Start

Register `InterceptlyDioInterceptor` into your `Dio` instance:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_dio/interceptly_dio.dart';

final navigatorKey = GlobalKey<NavigatorState>();

final dio = Dio(
  BaseOptions(baseUrl: 'https://api.example.com'),
)..interceptors.add(InterceptlyDioInterceptor());

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp(navigatorKey: navigatorKey));

  if (kDebugMode || kProfileMode) {
    Interceptly.init(
      navigatorKey: navigatorKey,
      settings: const InterceptlySettings(
        maxEntries: 1000,
      ),
    );
  }
}
```

---

## Features

- **Non-Intrusive**: Network errors or serialization quirks never break your application flow; all original errors pass through untouched.
- **CancelToken Support**: Cancelled requests via `CancelToken` are recorded with `errorType: 'cancel'` and marked as errors.
- **Rich Payload Support**: Captures JSON, URL-encoded forms, `FormData` multipart uploads, and binary responses.
- **Error Capture**: Preserves full error messages, stack traces, and HTTP status codes (such as 4xx/5xx responses).
- **Replay Ready**: Recorded Dio requests can be edited and re-sent directly from the Interceptly UI.
- **Network Simulation**: Fully honors global latency, throttling, and offline profiles set in Interceptly.

---

## Configuration Options & SPI Injection

`InterceptlyDioInterceptor` implements `HttpCaptureAdapter`. By default it uses `DefaultHttpTrafficCollector()`, which automatically coordinates with `InspectorSession.instance`. You can also inject a custom `HttpTrafficCollector`:

```dart
// Custom collector:
final collector = MyCustomHttpTrafficCollector();
final customDio = Dio()..interceptors.add(
  InterceptlyDioInterceptor(collector),
);
```

---

## License

MIT License - see [LICENSE](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE) for details.
