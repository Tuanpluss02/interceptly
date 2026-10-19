# 08 — Common Pitfalls & Debugging

> **Scope:** Frequent issues, debugging checklist, key files to inspect.

---

## 8.1 Common Pitfalls & Fixes

| Symptom | Root Cause | Fix |
|---------|------------|-----|
| **Tests flaky / state leaks** | Missing `resetForTesting()` | Add `await InspectorSession.resetForTesting()` to **both** `setUp()` AND `tearDown()` |
| **Floating button disappears after navigation** | Missing `navigatorObservers` | Add `navigatorObservers: [Interceptly.navigatorObserver]` to `MaterialApp` |
| **Inspector opens in release build** | `init()` not wrapped in debug check | Wrap: `if (kDebugMode \|\| kProfileMode) Interceptly.init(...)` |
| **pana score < 160** | Missing CHANGELOG, outdated deps, example fails | Fix per pana output: `melos run pana` shows details |
| **Adapter tests fail after core change** | SPI signature drift | Update adapter to match new SPI signatures in same PR |
| **Memory grows unbounded** | `maxEntries` not respected / `clear()` not called | Verify `MemoryIndex` eviction, `clear()` calls `_memoryIndex.clear()` |
| **WebSocket frames missing** | Not using `RealtimeSessionScope` | Delegate to `scope.send()`/`receive()`/`close()`, not collector directly |
| **Request bodies empty in inspector** | Adapter not capturing body | Ensure `bodyBytes` passed to `collector.begin()` / `scope.complete()` |
| **Truncation not detected** | `responseTruncatedAtStorage` not passed | For streaming: `complete(..., responseTruncatedAtStorage: isTruncated)` |
| **Network simulation not working** | `SimulatedNetworkException` not handled | Catch in adapter `onRequest`, reject with appropriate error |

---

## 8.2 Debugging Checklist for AI Agents

When something breaks, follow in order:

### 1. Static Analysis First
```bash
melos run analyze
# Fix ALL errors/warnings/lints before proceeding
```

### 2. Run Specific Test
```bash
# Single test file
flutter test packages/interceptly/test/session/truncation_loss_test.dart

# Single test by name
flutter test --plain-name "writer_isolate preserves original responseSizeBytes"

# With verbose output
flutter test -v packages/interceptly/test/session/isolate_resilience_test.dart
```

### 3. Check Isolate Logs
```dart
// In debug mode, these appear in console:
debugPrint('[Interceptly] capture failed (request unaffected): $e');
debugPrint('[Interceptly] startRequest capture failed: $e');
debugPrint('[Interceptly] background init failed: $e');
```

### 4. Verify SPI Delegation
```dart
// Add temporary prints in adapter to trace:
print('[DEBUG] collector.begin called for ${request.uri}');
print('[DEBUG] scope.complete called with status ${response.statusCode}');
print('[DEBUG] scope.fail called with error $error');
```

### 5. Inspect WriterIsolate State
```dart
// In test or debug:
final pipeline = InspectorSession.instance.capturePipeline;
print('WriterIsolate ready: ${pipeline.isInitialized}');
print('Queue length: ${pipeline._writerIsolate?.queueLength}');
print('Last batch duration: ${pipeline._writerIsolate?.lastProcessingDuration}');
```

### 6. Check MemoryIndex
```dart
final session = InspectorSession.instance;
print('Entries: ${session._memoryIndex.length}/${session._memoryIndex.capacity}');
print('Filter: ${session._filter}');
print('Search: ${session._search.query}');
```

### 7. Verify BodyStore
```dart
// Check if bodies written to disk
final store = InspectorSession.instance._bodyStore;
print('BodyStore dir: ${store.dir.path}');
print('Files: ${await store.dir.list().toList()}');
```

---

## 8.3 Key Files to Read First (Priority Order)

| Priority | File | Why |
|----------|------|-----|
| 1 | `packages/interceptly/lib/adapter.dart` | SPI surface — all contracts |
| 2 | `packages/interceptly/lib/src/adapter/http_traffic_collector.dart` | HTTP collector impl |
| 3 | `packages/interceptly/lib/src/adapter/http_capture_scope.dart` | Scope lifecycle |
| 4 | `packages/interceptly/lib/src/session/inspector_session.dart` | Session singleton |
| 5 | `packages/interceptly/lib/src/session/capture_pipeline.dart` | Isolate bridge |
| 6 | `packages/interceptly/lib/src/session/writer_isolate.dart` | Background processing |
| 7 | `packages/interceptly/lib/src/model/body_truncation.dart` | Truncation model |
| 8 | `packages/interceptly_dio/lib/src/interceptly_dio_interceptor.dart` | Reference HTTP adapter |
| 9 | `packages/interceptly_web_socket/lib/src/interceptly_web_socket_channel.dart` | Reference Realtime adapter |

---

## 8.4 Test Debugging Patterns

### Flaky Test Isolation
```dart
// Each test MUST reset
setUp(() async {
  await InspectorSession.resetForTesting();  // Resets singleton + isolate
  // ... configure
});

tearDown(() async {
  await InspectorSession.resetForTesting();  // Clean up for next test
});
```

### Timeout Issues
```dart
// Increase timeout for slow tests
@Timeout(Duration(minutes: 2))
test('stress test with many requests', () async { ... });

// Or use fake_async for time-dependent logic
test('timeout handling', () async {
  final fake = FakeAsync();
  fake.run((async) {
    // ... test
    async.elapse(Duration(seconds: 50));
  });
});
```

### Isolate Communication Debugging
```dart
// In writer_isolate.dart, add temporary logging:
void _processMessage(RawCapture capture) {
  if (kDebugMode) print('[WriterIsolate] Processing ${capture.id}');
  // ...
  if (kDebugMode) print('[WriterIsolate] Replying ${summary.id}');
}
```

---

## 8.5 CI Failure Debugging

| CI Job | Common Failure | Debug Locally |
|--------|----------------|---------------|
| `lint-and-format` | Format/analyze issues | `melos run format && melos run analyze` |
| `test` | Test failure | `melos run test:core` then specific test |
| `pana-and-example` | pana < 160 / example fail | `melos run pana` + `cd packages/interceptly/example && flutter analyze && flutter test` |

### pana Debugging
```bash
# Run pana with verbose output
cd packages/interceptly
pana --no-warning --exit-code-threshold 1 -j 2>&1 | head -100
```

---

## 8.6 Quick Reference: Where Things Live

| Need to... | Look in |
|------------|---------|
| Add new SPI method | `adapter.dart` + `http_traffic_collector.dart` / `realtime_traffic_collector.dart` |
| Change truncation logic | `body_decode_service.dart`, `raw_capture.dart`, `body_truncation.dart` |
| Fix storage bug | `body_store.dart`, `realtime_body_store.dart`, `capture_pipeline.dart` |
| Fix session clearing | `inspector_session.dart` (`clear`, `clearRest`, `clearRealtime`) |
| Add new adapter | Copy `interceptly_dio` pattern, implement SPI |
| Fix WebSocket frames | `realtime_session_scope.dart`, `realtime_traffic_collector.dart` |
| Debug isolate crash | `writer_isolate.dart` (catch zones, error handling) |
| Change simulation | `model/network_simulation.dart`, `http_traffic_collector.dart` |