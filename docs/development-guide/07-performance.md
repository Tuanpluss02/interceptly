# 07 — Performance Guardrails

> **Scope:** Hot-path rules, memory budgets, profiling hooks.

---

## 7.1 Hot Path Rules (Main Isolate)

| Operation | Allowed? | Alternative |
|-----------|----------|-------------|
| JSON parse/decode | ❌ | `WriterIsolate` |
| File I/O (read/write) | ❌ | `BodyStore` via isolate |
| Large list iteration (>100 items) | ⚠️ | Background isolate |
| `notifyListeners()` | ✅ Debounced (50ms) | `_coalesceNotifyTimer` |
| `shouldCapture(url)` | ✅ Sync, < 1ms | Keep simple, no I/O |
| `Map`/`List` allocation | ✅ Small (< 50) | Reuse where possible |
| `String` interpolation | ✅ Small | Avoid in hot loop |
| Isolate spawn | ❌ | Use existing `WriterIsolate` |

### Critical: What MUST Stay Off Main Thread

```dart
// ❌ NEVER on main isolate
jsonDecode(largeJsonString);           // → WriterIsolate
await file.writeAsBytes(bytes);        // → BodyStore via isolate
compute(expensiveParsing, data);       // → WriterIsolate (already isolated)
largeList.map(expensiveTransform);     // → WriterIsolate or batch

// ✅ OK on main isolate (metadata only)
InspectorSession.instance.entries;     // RequestSummary only
session.filter = RequestFilter(...);   // Triggers debounced notify
entry.requestTruncation;               // Small enum
```

---

## 7.2 Memory Budgets (InterceptlySettings Defaults)

```dart
const InterceptlySettings(
  // Request history
  maxEntries: 5000,                    // RequestSummary objects in RAM
  
  // Per-body limits
  maxBodyBytes: 5 * 1024 * 1024,       // 5MB hard cap before truncation
  bodyOffloadThreshold: 50 * 1024,     // 50KB → offload to disk
  previewTruncationBytes: 16 * 1024,   // 16KB preview for pending rows
  maxUiPreviewBytes: 2 * 1024 * 1024,  // 2MB max decoded for detail view
  
  // WebSocket
  maxFramesPerSession: 1000,           // Frames per connection (ring buffer)
  
  // Pipeline
  maxQueuedEvents: 500,                // Pre-init queue buffer
  pendingTimeout: Duration(seconds: 45), // In-flight request timeout
);
```

### Memory Footprint Estimates

| Component | Estimate (per entry) |
|-----------|---------------------|
| `RequestSummary` | ~2-4 KB (metadata only) |
| 5000 entries | ~10-20 MB |
| `BodyStore` disk | Bodies > 50KB each |
| `RealtimeBodyStore` | Frames ~1-2 KB each |
| 1000 frames/session | ~1-2 MB/session |

---

## 7.3 WriterIsolate Processing Budget

```dart
// WriterIsolate processes sequentially — measure per batch
class WriterIsolate {
  // Exposed for profiling
  Duration lastProcessingDuration;  // Time to process one RawCapture batch
  int queueLength;                  // Pending RawCapture count
  
  // Target: < 16ms per batch (60fps headroom)
  // Typical: 1-5ms for JSON decode + truncation + disk write
}
```

### Processing Steps (Per `RawCapture`)

1. **Body decode** — JSON, FormData, multipart summary
2. **Truncation compute** — `BodyDecodeService.truncate()`
3. **Disk write** — If > `bodyOffloadThreshold`, write to `BodyStore`
4. **Build `RequestSummary`** — Metadata only, no body
5. **SendPort reply** — Back to main isolate

---

## 7.4 Network Simulation Overhead

```dart
// Simulation adds latency but minimal CPU
// delayForChunk() calculates delay based on KB/s
// Actual delay via Future.delayed() — yields to event loop

Duration delayForChunk(int chunkBytes) {
  if (downloadKbps <= 0) return Duration.zero;
  final kb = chunkBytes / 1024;
  final ms = (kb / downloadKbps * 1000).round();
  return Duration(milliseconds: ms);
}
```

---

## 7.5 Profiling Hooks

### In Tests/Benchmarks

```dart
// CapturePipeline metrics
final pipeline = InspectorSession.instance.capturePipeline;
pipeline.metrics.queueDepth;           // Pending captures
pipeline.metrics.isolateLatency;       // WriterIsolate processing time

// WriterIsolate state
final isolate = pipeline._writerIsolate;
isolate?.isReady;
isolate?.queueLength;
isolate?.lastProcessingDuration;

// MemoryIndex stats
final index = InspectorSession.instance._memoryIndex;
index.length;                          // Current entries
index.capacity;                        // maxEntries
```

### Manual Profiling

```dart
// Enable verbose isolate logging
if (kDebugMode) {
  debugPrint('[Interceptly] WriterIsolate batch: ${duration.inMilliseconds}ms');
}
```

---

## 7.6 Optimization Patterns

### 1. Batch Notifications (Already Implemented)

```dart
// InspectorSession._coalesceNotifyTimer
// Batches notifyListeners() calls within 50ms window
void _scheduleNotify() {
  _coalesceNotifyTimer ??= Timer(const Duration(milliseconds: 50), () {
    _coalesceNotifyTimer = null;
    if (!_hasPendingCoalescedNotify) return;
    _hasPendingCoalescedNotify = false;
    notifyListeners();
  });
  _hasPendingCoalescedNotify = true;
}
```

### 2. Lazy Body Loading (Already Implemented)

```dart
// loadDetailById() reads from disk ONLY when detail viewed
Future<RequestRecord?> loadDetailById(String id) async {
  final summary = _memoryIndex.getById(id);
  if (summary == null) return null;
  
  // Body loaded on-demand from BodyStore
  final requestBody = await _bodyStore.read('${id}_req');
  final responseBody = await _bodyStore.read('${id}_res');
  
  return RequestRecord(summary: summary, requestBody: requestBody, responseBody: responseBody);
}
```

### 3. Ring Buffer Eviction (Already Implemented)

```dart
// MemoryIndex uses RingBuffer — O(1) add, O(1) evict LRU
class RingBuffer<T> {
  void add(T item) {
    if (_length == _capacity) _head = (_head + 1) % _capacity; // Overwrite oldest
    _buffer[_tail] = item;
    _tail = (_tail + 1) % _capacity;
    _length = min(_length + 1, _capacity);
  }
}
```

---

## 7.7 Performance Anti-Patterns to Avoid

| Anti-Pattern | Why Bad | Fix |
|--------------|---------|-----|
| `jsonDecode` in adapter `onResponse` | Blocks main thread | Use `scope.bindResponseStream()` or let `WriterIsolate` decode |
| `await file.writeAsBytes()` in adapter | Blocks main thread + I/O | Use `RawCapture` → `CapturePipeline` → `WriterIsolate` → `BodyStore` |
| Large `List` in `RequestSummary` | Bloats memory index | Store only metadata; bodies on disk |
| Missing `maxEntries` / no eviction | Unbounded growth | Always configure `InterceptlySettings.maxEntries` |
| Synchronous `shouldCapture` doing I/O | Blocks every request | Keep predicate pure: `url.contains(...)` only |

---

## 7.8 Tuning for High-Volume Apps

```dart
// For apps with 1000+ req/min:
InterceptlySettings(
  maxEntries: 2000,           // Reduce history
  maxBodyBytes: 1024 * 1024,  // 1MB cap
  bodyOffloadThreshold: 10 * 1024, // Offload earlier
  maxQueuedEvents: 200,       // Smaller pre-init buffer
  pendingTimeout: Duration(seconds: 30),
);

// For WebSocket-heavy apps:
InterceptlySettings(
  maxFramesPerSession: 500,   // Reduce frame history
  maxBodyBytes: 256 * 1024,   // Smaller frame cap
);
```

---

## 7.9 Key Files for Performance Work

| File | Purpose |
|------|---------|
| `writer_isolate.dart` | Background processing, batch timing |
| `capture_pipeline.dart` | Queue management, pre-init buffer |
| `body_store.dart` | Disk offload threshold, read/write |
| `memory_index.dart` | Ring buffer, eviction |
| `body_decode_service.dart` | Truncation logic |
| `pending_tracker.dart` | In-flight timeout cleanup |
| `realtime_body_store.dart` | Frame ring buffer |