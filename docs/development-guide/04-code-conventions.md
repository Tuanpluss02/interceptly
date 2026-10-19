# 04 — Code Conventions & Patterns

> **Scope:** Type safety, adapter patterns, async/error handling, naming conventions.

---

## 4.1 Type Safety (Non-Negotiable)

```dart
// ✅ GOOD: Explicit types, no dynamic
Future<HttpCaptureScope> begin({
  required String method,
  required Uri uri,
  Map<String, String>? headers,
  Uint8List? bodyBytes,
  String? contentType,
}) async { ... }

// ❌ BAD: dynamic, loose typing
Future begin(dynamic request) async { ... }

// ✅ GOOD: Abstract interface class for SPI
abstract interface class HttpTrafficCollector { ... }

// ✅ GOOD: Nullable types explicit
Uint8List? bodyBytes;
String? contentType;
```

---

## 4.2 Adapter Patterns — Thin Delegation

### HTTP Adapter Template

```dart
import 'package:interceptly/adapter.dart';
import 'package:interceptly/capture_guard.dart';

class InterceptlyXxxInterceptor extends Interceptor {
  final HttpTrafficCollector collector;
  
  InterceptlyXxxInterceptor([HttpTrafficCollector? c]) 
    : collector = c ?? HttpTrafficCollector.instance;
  
  // 1. REQUEST — may throw SimulatedNetworkException
  Future<void> onRequest(RequestOptions options, Handler handler) async {
    // ALWAYS check shouldCapture first
    if (!collector.shouldCapture(options.uri)) { 
      handler.next(options); 
      return; 
    }
    
    final scope = await collector.begin(
      method: options.method,
      uri: options.uri,
      headers: normalizeHeaders(options.headers),
      bodyBytes: encodeBodyBytes(options.data),
      contentType: options.contentType,
    );
    
    options.extra[_scopeKey] = scope;  // Store for response/error
    handler.next(options);
  }
  
  // 2. RESPONSE — fire and forget, MUST NOT block
  Future<void> onResponse(Response response, Handler handler) async {
    final scope = response.extra.remove(_scopeKey) as HttpCaptureScope?;
    if (scope == null && !collector.shouldCapture(response.requestOptions.uri)) {
      handler.next(response);
      return;
    }
    
    // Delegate to scope.complete() via unawaited + guardCaptureAsync
    unawaited(guardCaptureAsync(() async {
      await scope!.complete(
        statusCode: response.statusCode ?? 200,
        headers: normalizeHeaders(response.headers),
        bodyBytes: encodeBodyBytes(response.data),
        contentType: response.headers.contentType,
        durationMs: elapsedMs,
      );
    }));
    
    handler.next(response);
  }
  
  // 3. ERROR — fire and forget
  void onError(Error err, Handler handler) {
    final scope = err.requestOptions.extra.remove(_scopeKey) as HttpCaptureScope?;
    if (scope == null && !collector.shouldCapture(err.requestOptions.uri)) {
      handler.next(err);
      return;
    }
    
    unawaited(guardCapture(() {
      scope!.fail(
        err.error ?? err,
        errorType: err.type.name,
        errorMessage: err.message,
        statusCode: err.response?.statusCode,
        responseHeaders: err.response?.headers,
        responseBodyBytes: encodeBodyBytes(err.response?.data),
      );
    }));
    
    handler.next(err);
  }
}
```

### Realtime Adapter Template

```dart
class InterceptlyXxxChannel extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  final RealtimeTrafficCollector collector;
  late final RealtimeSessionScope scope;
  
  InterceptlyXxxChannel(
    Channel inner, {
    Uri? uri,
    String? sessionId,
    RealtimeTrafficCollector? collector,
  }) : collector = collector ?? RealtimeTrafficCollector.instance {
    
    scope = this.collector.openSession(
      uri: uri ?? Uri(scheme: 'ws', host: 'unknown'),
      sessionId: sessionId,
    );
    
    // Hook inner channel events → scope
    inner.stream.listen((data) => scope.receive(type: FrameType.text, payload: data));
    inner.sink.onAdd = (data) => scope.send(type: FrameType.text, payload: data);
    inner.done.then((_) => scope.close(code: inner.closeCode, reason: inner.closeReason));
  }
}
```

---

## 4.3 SPI Compliance Checklist (Adapters Must)

- [ ] Expose `collector` field (e.g. `final HttpTrafficCollector collector;`)
- [ ] Call `collector.shouldCapture(uri)` before ANY capture work
- [ ] Handle `SimulatedNetworkException` from `collector.begin()`
- [ ] Use `guardCapture` / `guardCaptureAsync` for ALL capture completions
- [ ] Delegate to `HttpCaptureScope` / `RealtimeSessionScope`, NOT directly to collector
- [ ] For streaming: use `scope.bindResponseStream()` or `scope.send/receive()`
- [ ] Pass `responseTruncatedAtStorage` when using streaming

---

## 4.4 Async Patterns

| Pattern | When to Use | Example |
|---------|-------------|---------|
| `await` | Sequential dependency, must complete before next | `await scope.complete(...)` in test |
| `unawaited(guardCaptureAsync(...))` | Fire-and-forget capture (must not block response) | `onResponse`, `onError` in adapters |
| `Future.microtask(() => ...)` | Defer to next event loop (UI updates) | `notifyListeners()` in session |
| `compute()` / Isolate | Heavy parsing | NOT used — `WriterIsolate` handles this |

### `guardCapture` / `guardCaptureAsync`

```dart
import 'package:interceptly/capture_guard.dart';

// Synchronous
guardCapture(() => synchronousWork());  // Returns void, swallows exception

// Asynchronous  
await guardCaptureAsync(() async => await asyncWork());  // Returns Future, swallows

// In debug mode: logs with [Interceptly] prefix
// In release: completely swallowed (capture failure must not affect app)
```

---

## 4.5 Error Handling

```dart
// ✅ GOOD: Try/capture pattern
try {
  final scope = await collector.begin(...);
  options.extra[_key] = scope;
} on SimulatedNetworkException catch (e) {
  handler.reject(DioException(..., error: e));  // Simulation rejection
  return;
} catch (e, st) {
  if (kDebugMode) debugPrint('[Interceptly] capture failed: $e\n$st');
  // Continue — capture failure must not break request
}

// ✅ GOOD: Fire-and-forget with guardCaptureAsync
unawaited(guardCaptureAsync(() async {
  await scope.complete(...);  // Any exception logged, not thrown
}));

// ❌ BAD: Letting capture exception propagate
await scope.complete(...);  // If this throws, it breaks the response!
```

---

## 4.6 Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Files | `snake_case.dart` | `http_traffic_collector.dart` |
| Classes | `PascalCase` | `HttpTrafficCollector` |
| Private members | `_camelCase` | `_memoryIndex` |
| Constants (top-level) | `SCREAMING_SNAKE` | `DEFAULT_MAX_ENTRIES` |
| Constants (class) | `lowerCamelCase` | `defaultMaxEntries` |
| SPI interfaces | `PascalCase` | `HttpTrafficCollector` |
| Test files | `*_test.dart` | `session_truncation_test.dart` |
| Test groups | `PascalCase` | `group('WriterIsolate Resilience', ...)` |
| Private test helpers | `_PascalCase` | `class _SpyCollector` |

---

## 4.7 Import Organization

```dart
// 1. Dart SDK
import 'dart:async';
import 'dart:typed_data';

// 2. Flutter SDK
import 'package:flutter/foundation.dart';

// 3. External packages
import 'package:dio/dio.dart';

// 4. Internal (interceptly)
import 'package:interceptly/adapter.dart';
import 'package:interceptly/capture_guard.dart';

// 5. Relative (same package)
import 'src/private_helper.dart';
```

---

## 4.8 Documentation Comments

```dart
/// Brief one-line summary.
///
/// Longer explanation if needed. Blank line separates summary from body.
///
/// **Parameters:**
/// - `paramName`: Description
///
/// **Returns:** What it returns.
///
/// **Throws:** When it throws.
///
/// **See also:** [RelatedClass], [relatedFunction].
Future<HttpCaptureScope> begin({...}) async { ... }
```

- Public SPI: Full doc comments
- Internal: Minimal or self-explanatory
- No inline `//` comments — use docstrings only