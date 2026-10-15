# Interceptly — Agent Install & Usage Guide

You are integrating Interceptly, a client-agnostic network & realtime traffic
inspector for Flutter, into an existing Flutter project. Follow these steps in
order. Do not skip verification.

## 1. Detect the project setup

- Read the app's `pubspec.yaml`. Note the Flutter/Dart SDK constraints and
  which networking clients are already used: `dio`, `http`, `chopper`,
  `web_socket_channel` (note each version).
- Find where `runApp` / `MaterialApp` (or `MaterialApp.router`) is built and
  whether a global `navigatorKey` already exists.

## 2. Add dependencies (hosted only)

```bash
flutter pub add interceptly:^2.1.0
```

Then add only the adapters matching the clients detected in step 1:

```bash
flutter pub add interceptly_dio:^1.0.0        # if dio is used
flutter pub add interceptly_http:^1.0.0       # if package:http is used
flutter pub add interceptly_chopper:^1.0.0    # if chopper is used
flutter pub add interceptly_web_socket:^1.0.0 # if web_socket_channel is used
```

Rules:

- Never use `path:` dependencies for these packages in a consumer app.
- Never downgrade the app's existing `dio` / `http` / `chopper` /
  `web_socket_channel` versions to satisfy adapters; report a conflict instead.

## 3. Wire `Interceptly.init` (debug/profile only)

Ask the user first: most projects use flavors (dev/staging/prod). Confirm in
which flavors the inspector should be enabled — default recommendation is
everywhere except production store builds. If the project defines its own
`isDev` / `isStaging` flags or `--dart-define` environment markers, use those
instead of (or in addition to) the `kDebugMode || kProfileMode` check below,
and state which condition you chose.

- Ensure a global key exists: `final navigatorKey = GlobalKey<NavigatorState>();`
- Pass it to `MaterialApp` (`navigatorKey:`) or to `GoRouter` (`navigatorKey:`).
- Only if the floating button disappears after route transitions, additionally set `navigatorObservers: [Interceptly.navigatorObserver]` on `MaterialApp`. Do not present this as the default setup.
- After `runApp`, initialize only in debug/profile:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp(navigatorKey: navigatorKey));

  if (kDebugMode || kProfileMode) {
    Interceptly.init(
      navigatorKey: navigatorKey,
      settings: const InterceptlySettings(maxEntries: 1000),
    );
  }
}
```

- The SDK has no release guard: `Interceptly.init` works in any build mode, so always wrap it in `if (kDebugMode || kProfileMode)` or the inspector ships to production users.

## 4. Attach adapters

Dio:

```dart
import 'package:interceptly_dio/interceptly_dio.dart';

final dio = Dio()..interceptors.add(InterceptlyDioInterceptor());
```

`package:http`:

```dart
import 'package:http/http.dart' as http;
import 'package:interceptly_http/interceptly_http.dart';

final client = InterceptlyHttpClient(http.Client());
```

Chopper:

```dart
import 'package:interceptly_chopper/interceptly_chopper.dart';

final chopper = ChopperClient(
  interceptors: [InterceptlyChopperInterceptor()],
);
```

WebSocket:

```dart
import 'package:interceptly_web_socket/interceptly_web_socket.dart';

final channel = InterceptlyWebSocketChannel.connect(
  Uri.parse('wss://example.com/socket'),
);
```

Optional: skip noisy URLs so they cost zero memory/disk:

```dart
InterceptlySettings(
  shouldCapture: (url) =>
      !url.contains('/health-check') && !url.contains('/analytics'),
)
```

`shouldCapture` runs synchronously per request: keep it fast and non-blocking.

## 5. Verify

1. Run `flutter analyze` — zero new issues from these changes.
2. Run the app, trigger one request per attached client.
3. Open the inspector via the floating button and confirm one row per request,
   with request/response bodies visible.
4. If a row is missing, check `shouldCapture` and confirm the right adapter
   wraps the client that actually performs the call.

## 6. Everyday usage (for the developer)

- Browse/filter traffic in the inspector overlay; tap a row for detail tabs.
- Replay: edit headers/body in the detail page and re-send.
- Export a record as HAR, cURL, or Postman collection from the detail page.
- Simulate conditions via `Interceptly.instance.setNetworkSimulation(...)`
  (Offline, Slow 3G, Fast 3G, 4G, Wi-Fi, custom profiles).
- Programmatic control: `Interceptly.showInspector(context)`,
  `Interceptly.hideFloatingButtonForSession()` /
  `Interceptly.showFloatingButtonForSession()`, `Interceptly.detach()`.

## 7. Troubleshooting

- Inspector opens in release builds too if `init` was called there: the SDK has no release guard, so the `kDebugMode || kProfileMode` wrapper at the call site is the only protection.
- Floating button disappears after navigation: `navigatorObservers` is missing.
- iOS simulator build fails on deployment target: the app needs
  `platform :ios, '15.0'` (current Xcode supports 15.0+ only).
- Developing against a local Interceptly checkout: use
  `pubspec_overrides.yaml` with `path:` overrides (melos generates these);
  never commit `path:` deps in a consumer app.
