# interceptly_chopper

[![pub package](https://img.shields.io/pub/v/interceptly_chopper.svg)](https://pub.dev/packages/interceptly_chopper)
[![license](https://img.shields.io/github/license/Tuanpluss02/interceptly.svg)](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE)

Chopper interceptor adapter for the [Interceptly](https://pub.dev/packages/interceptly) network inspector in Flutter.

`InterceptlyChopperInterceptor` records all outgoing requests and incoming responses sent through [Chopper](https://pub.dev/packages/chopper) services, with full fidelity for path parameters, query maps, multipart parts, and response bodies.

---

## Installation

Add both `interceptly` (the core inspector) and `interceptly_chopper` to your project:

```bash
flutter pub add interceptly
flutter pub add interceptly_chopper
```

---

## Quick Start

Add `InterceptlyChopperInterceptor` to your `ChopperClient`:

```dart
import 'package:chopper/chopper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_chopper/interceptly_chopper.dart';

final navigatorKey = GlobalKey<NavigatorState>();

final chopper = ChopperClient(
  baseUrl: Uri.parse('https://api.example.com'),
  interceptors: [
    InterceptlyChopperInterceptor(),
  ],
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp(navigatorKey: navigatorKey));

  if (kDebugMode || kProfileMode) {
    Interceptly.init(navigatorKey: navigatorKey);
  }
}
```

---

## Features

- **Bidirectional Capture**: Hooks both request and response phases in Chopper's interceptor chain.
- **Robust Parameter Handling**: Accurately formats URL queries and query maps without mutating the outbound request.
- **Multipart & Binary Support**: Seamlessly captures multipart body definitions and binary payloads.
- **Error Preservation**: Records HTTP error responses and asynchronous transport exceptions without leaking state.
- **Non-Disruptive**: Serialization or inspection failures are safely guarded and never crash the application.

---

## Configuration Options & SPI Injection

`InterceptlyChopperInterceptor` implements `HttpCaptureAdapter`. By default it uses `DefaultHttpTrafficCollector()`, which automatically coordinates with `InspectorSession.instance`. You can also inject a custom `HttpTrafficCollector`:

```dart
// Custom collector:
final collector = MyCustomHttpTrafficCollector();

final chopper = ChopperClient(
  interceptors: [
    InterceptlyChopperInterceptor(collector: collector),
  ],
);
```

---

## License

MIT License - see [LICENSE](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE) for details.
