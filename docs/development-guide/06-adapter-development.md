# 06 — Adding a New Adapter

> **Scope:** Step-by-step guide to create a new satellite adapter package.

---

## 6.1 Step-by-Step

### 1. Create Package Structure

```bash
mkdir -p packages/interceptly_foo/{lib/src,test}
```

### 2. `pubspec.yaml`

```yaml
name: interceptly_foo
description: "Foo client adapter for Interceptly network inspector."
version: 1.0.0
homepage: https://github.com/Tuanpluss02/interceptly
repository: https://github.com/Tuanpluss02/interceptly
issue_tracker: https://github.com/Tuanpluss02/interceptly/issues
documentation: https://pub.dev/documentation/interceptly_foo/latest/

environment:
  sdk: '>=3.5.0 <4.0.0'
  flutter: ">=3.24.0"

dependencies:
  flutter:
    sdk: flutter
  interceptly: ^2.2.0   # Match core SPI version
  foo_client: ^1.0.0    # Your networking library

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  mockito: ^5.0.0       # For SPI verification tests
  build_runner: ^2.4.0  # For mockito generation

flutter:
  plugin:
    platforms:
      android:
        package: dev.stormx.interceptly_foo
        pluginClass: InterceptlyFooPlugin
      ios:
        pluginClass: InterceptlyFooPlugin
```

### 3. Export Public API

```dart
// lib/interceptly_foo.dart
library interceptly_foo;

export 'src/interceptly_foo_interceptor.dart';
```

### 4. Implement HTTP Adapter

```dart
// lib/src/interceptly_foo_interceptor.dart
import 'package:foo_client/foo_client.dart';
import 'package:interceptly/adapter.dart';
import 'package:interceptly/capture_guard.dart';

class InterceptlyFooInterceptor extends FooInterceptor 
    implements HttpCaptureAdapter {
  
  final HttpTrafficCollector collector;
  
  InterceptlyFooInterceptor([HttpTrafficCollector? c]) 
    : collector = c ?? DefaultHttpTrafficCollector(),
      super() {
    // Register with FooClient
    FooClient.globalInterceptors.add(this);
  }
  
  @override
  InspectorSession get session => collector.session;
  
  @override
  Future<void> onRequest(FooRequest request, FooHandler handler) async {
    // 1. ALWAYS check shouldCapture FIRST
    if (!collector.shouldCapture(request.uri)) {
      handler.next(request);
      return;
    }
    
    // 2. Begin capture (may throw SimulatedNetworkException)
    final scope = await collector.begin(
      method: request.method,
      uri: request.uri,
      headers: request.headers,
      bodyBytes: request.bodyBytes,
      contentType: request.headers['content-type'],
    );
    
    // 3. Store scope for response/error
    request.extra['interceptly_scope'] = scope;
    handler.next(request);
  }
  
  @override
  Future<void> onResponse(FooResponse response, FooHandler handler) async {
    final scope = response.request.extra.remove('interceptly_scope') as HttpCaptureScope?;
    
    if (scope == null && !collector.shouldCapture(response.request.uri)) {
      handler.next(response);
      return;
    }
    
    // 4. Fire-and-forget completion — MUST NOT block response
    unawaited(guardCaptureAsync(() async {
      await scope!.complete(
        statusCode: response.statusCode,
        headers: response.headers,
        bodyBytes: response.bodyBytes,
        contentType: response.headers['content-type'],
        durationMs: response.elapsedMilliseconds,
      );
    }));
    
    handler.next(response);
  }
  
  @override
  void onError(FooRequest request, Object error, FooHandler handler) {
    final scope = request.extra.remove('interceptly_scope') as HttpCaptureScope?;
    
    if (scope == null && !collector.shouldCapture(request.uri)) {
      handler.next(request, error);
      return;
    }
    
    unawaited(guardCapture(() {
      scope!.fail(
        error,
        errorType: error.runtimeType.toString(),
        errorMessage: error.toString(),
        statusCode: (error as FooError?)?.statusCode,
      );
    }));
    
    handler.next(request, error);
  }
  
  // Optional: Streaming support if FooClient supports it
  @override
  Stream<List<int>> bindResponseStream(...) { ... }
}
```

### 5. Implement Realtime Adapter (if applicable)

```dart
// lib/src/interceptly_foo_realtime.dart
class InterceptlyFooRealtimeChannel extends FooWebSocketChannel 
    implements RealtimeCaptureAdapter {
  
  final RealtimeTrafficCollector collector;
  late final RealtimeSessionScope scope;
  
  InterceptlyFooRealtimeChannel(
    FooWebSocketChannel inner, {
    Uri? uri,
    String? sessionId,
    RealtimeTrafficCollector? collector,
  }) : collector = collector ?? DefaultRealtimeTrafficCollector(),
       super(inner) {
    
    scope = collector.openSession(
      uri: uri ?? Uri(scheme: 'ws', host: 'unknown'),
      sessionId: sessionId,
    );
    
    // Hook events
    inner.onMessage = (data) => scope.receive(
      type: data is String ? FrameType.text : FrameType.binary,
      payload: data,
    );
    
    inner.onSend = (data) => scope.send(
      type: data is String ? FrameType.text : FrameType.binary,
      payload: data,
    );
    
    inner.onClose = (code, reason) => scope.close(code: code, reason: reason);
  }
  
  @override InspectorSession get session => collector.session;
  @override RealtimeTrafficCollector get collector => _collector;
}
```

### 6. Add Tests

```dart
// test/interceptly_foo_interceptor_test.dart
import 'package:interceptly/adapter.dart';
import 'package:interceptly_foo/interceptly_foo.dart';
import 'package:mockito/mockito.dart';

class _SpyHttpCollector extends Mock implements HttpTrafficCollector {}

void main() {
  group('InterceptlyFooInterceptor', () {
    late _SpyHttpCollector spy;
    late InterceptlyFooInterceptor interceptor;
    
    setUp(() {
      spy = _SpyHttpCollector();
      when(spy.shouldCapture(any)).thenReturn(true);
      interceptor = InterceptlyFooInterceptor(spy);
    });
    
    test('delegates request to collector.begin', () async {
      final request = FooRequest.get(Uri.parse('https://api.example.com'));
      final handler = _FakeHandler();
      
      await interceptor.onRequest(request, handler);
      
      verify(spy.begin(
        method: 'GET',
        uri: Uri.parse('https://api.example.com'),
        headers: anyNamed('headers'),
        bodyBytes: anyNamed('bodyBytes'),
        contentType: anyNamed('contentType'),
      )).called(1);
    });
    
    test('handles SimulatedNetworkException', () async {
      when(spy.begin(any)).thenThrow(SimulatedNetworkException('offline'));
      
      final request = FooRequest.get(Uri.parse('https://api.example.com'));
      final handler = _FakeHandler();
      
      await interceptor.onRequest(request, handler);
      
      verify(handler.reject(any)).called(1);
    });
    
    test('delegates response to scope.complete', () async {
      final scope = _FakeScope();
      when(spy.begin(any)).thenAnswer((_) async => scope);
      
      final request = FooRequest.get(Uri.parse('https://api.example.com'));
      final handler = _FakeHandler();
      
      await interceptor.onRequest(request, handler);
      
      final response = FooResponse.ok(request, body: '{}');
      await interceptor.onResponse(response, handler);
      
      verify(scope.complete(any)).called(1);
    });
  });
}
```

### 7. Run Quality Gates

```bash
# From repo root
melos bootstrap
melos run check
melos run pana
```

---

## 6.2 Adapter Checklist

| Requirement | Verification |
|-------------|--------------|
| Implements `HttpCaptureAdapter` / `RealtimeCaptureAdapter` | `implements` clause |
| Exposes `collector` and `session` getters | `@override` getters |
| Calls `collector.shouldCapture(uri)` first | `if (!collector.shouldCapture(...)) return` |
| Handles `SimulatedNetworkException` from `begin()` | `on SimulatedNetworkException catch (e)` |
| Uses `guardCaptureAsync` for completions | `unawaited(guardCaptureAsync(() async => await scope.complete(...)))` |
| Uses `guardCapture` for failures | `guardCapture(() => scope.fail(...))` |
| Delegates to `HttpCaptureScope` / `RealtimeSessionScope` | No direct `InspectorSession` calls |
| Streaming: uses `scope.bindResponseStream()` or `scope.send/receive()` | Correct method |
| Passes `responseTruncatedAtStorage` for streaming | `complete(..., responseTruncatedAtStorage: isTruncated)` |
| Tests cover: success, error, streaming, cancellation, simulation | Test file exists |
| `pubspec.yaml` declares correct `interceptly` version | `^X.Y` matching SPI |
| `CHANGELOG.md` added with initial version | File exists |

---

## 6.3 Reference Adapters (Study These)

| Adapter | HTTP/Realtime | Key Patterns |
|---------|---------------|--------------|
| `interceptly_dio` | HTTP | `Interceptor`, `onRequest`/`onResponse`/`onError`, streaming via `bindResponseStream` |
| `interceptly_http` | HTTP | `BaseClient` wrapper, `send()` with `bindResponseStream` |
| `interceptly_chopper` | HTTP | `Interceptor`, `amendRequest` for actual sent request |
| `interceptly_web_socket` | Realtime | `WebSocketChannel` wrapper, `RealtimeSessionScope` send/receive/close |

---

## 6.4 Version Policy for New Adapter

```yaml
# First release
version: 1.0.0
dependencies:
  interceptly: ^2.2.0  # Core SPI version
```

| Subsequent Change | Adapter Version |
|-------------------|-----------------|
| Bug fix, internal | Patch (1.0.1) |
| New feature, no SPI change | Minor (1.1.0) |
| Requires new core SPI param | Minor (1.1.0) + core minor |
| Core SPI breaking change | Major (2.0.0) + core major |