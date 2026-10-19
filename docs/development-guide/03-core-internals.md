# 03 — Core Architecture Deep-Dive

> **Scope:** `InspectorSession`, `CapturePipeline`/`WriterIsolate`, hybrid storage model, truncation logic.

---

## 3.1 `InspectorSession` — The Singleton Brain

**File:** `packages/interceptly/lib/src/session/inspector_session.dart`

### Singleton Access

```dart
InspectorSession.instance  // Global accessor
await InspectorSession.resetForTesting()  // Test isolation (CRITICAL)
```

### State

| Field | Type | Purpose |
|-------|------|---------|
| `_entries` | `List<RequestSummary>` | Capped history (maxEntries default 5000) |
| `_memoryIndex` | `MemoryIndex` | Fast lookup, filtering, search, grouping |
| `_capturePipeline` | `CapturePipeline` | WriterIsolate bridge |
| `_realtimeStore` | `RealtimeStore` | WebSocket session registry |
| `_pendingTracker` | `PendingTracker` | In-flight request timeouts |
| `_realtimeBodyStore` | `RealtimeBodyStore` | WebSocket frame disk storage |
| `_settings` | `InterceptlySettings` | Current configuration |

### Mutation Methods (Called by Collectors)

```dart
// Record a completed capture (from WriterIsolate via CapturePipeline)
void record(RawCapture capture) {
  // 1. Build RequestSummary from capture
  // 2. Insert into MemoryIndex (evicts LRU if > maxEntries)
  // 3. Notify listeners (debounced 50ms)
}

// Clear all / REST only / Realtime only — generation-fenced
Future<void> clear();
Future<void> clearRest();
Future<void> clearRealtime();
```

### Read Methods (Called by UI)

```dart
// Filtered, sorted entries for list view
List<RequestSummary> get entries;

// Load full detail (deserializes from disk if needed)
Future<RequestRecord?> loadDetailById(String id);

// Grouped by domain/endpoint for Network tab
Map<String, List<RequestSummary>> get groupedEntries;

// Search across URL, headers, body, frames
SearchController search;
RequestFilter _filter;
```

### Critical: Generation-Fenced Clearing

```dart
// Each clear increments _entriesVersion
// In-flight records with old generation are discarded
// Prevents race: clear() while records being written
```

---

## 3.2 `CapturePipeline` & `WriterIsolate` — Off-Main-Thread Processing

**Files:** `capture_pipeline.dart`, `writer_isolate.dart`

### Data Flow

```
Main Isolate                          Background Isolate (WriterIsolate)
─────────────────────────────────────────────────────────────────────────
InspectorSession.record(RawCapture)
    │
    ▼
CapturePipeline.enqueue()  ──────►  Receive RawCapture
    │                               │
    │  (if isolate not ready)       │  1. Decode/parse body (JSON, FormData, etc.)
    │  queue in _preInitQueue       │  2. Compute truncation (BodyTruncation)
    │                               │  3. Serialize to disk (BodyStore) if > threshold
    ▼                               │  4. Build RequestSummary (metadata only)
                                    │  5. Send back RequestSummary via SendPort
                            ◄──────────
    │
    ▼
InspectorSession receives summary
  → Updates MemoryIndex
  → Notifies listeners (debounced)
```

### Key Classes

#### `CapturePipeline`

```dart
class CapturePipeline {
  // Bounded queue for calls before isolate boots
  final BoundedEventQueue _preInitQueue;  // maxQueuedEvents (default 500)
  
  WriterIsolate? _writerIsolate;
  bool get isInitialized => _writerIsolate != null;

  Future<void> initialize();
  void enqueue(RawCapture capture);  // Called by InspectorSession.record()
  Future<void> clear();
  Future<void> dispose();
}
```

#### `WriterIsolate`

```dart
class WriterIsolate {
  // Single-threaded message loop processing RawCapture sequentially
  // Communicates via SendPort/ReceivePort pair
  
  // Metrics for profiling
  int get queueLength;
  bool get isReady;
  Duration lastProcessingDuration;
}
```

### Critical Rules

| Rule | Enforcement |
|------|-------------|
| **Never** JSON parse/decode on main isolate | All body processing in `WriterIsolate._processCapture()` |
| **Never** file I/O on main isolate | `BodyStore` writes happen in isolate |
| Order preserved | `WriterIsolate` processes sequentially |
| Bounded pre-init queue | `_preInitQueue` caps at `maxQueuedEvents` (500) |

---

## 3.3 Storage Model — Hybrid RAM + Disk

### Three-Tier Storage

| Layer | What Lives Here | Eviction Policy | Access Pattern |
|-------|-----------------|-----------------|----------------|
| `RequestSummary` (in `MemoryIndex`) | Metadata only: id, method, url, status, sizes, truncation flags, timestamps | LRU by `maxEntries` (5000) | Instant — UI list, search, filter |
| `BodyStore` (disk) | Full request/response bodies (JSON, binary, multipart summary) | Deleted when summary evicted or `clear()` | Lazy — `loadDetailById()` reads on demand |
| `RealtimeBodyStore` (disk) | WebSocket frames per session (FIFO ring buffer) | By `maxFramesPerSession` (1000) per session | Sequential — replay, detail view |

### `BodyStore` — RAM + Disk Hybrid

**File:** `body_store.dart`

```dart
class BodyStore {
  // In-memory cache for recently accessed bodies
  final Map<String, Uint8List> _memoryCache;
  // Disk directory for offloaded bodies
  final Directory _dir;
  
  // Threshold: bodies > bodyOffloadThreshold (50KB) go to disk
  Future<void> write(String id, Uint8List bytes);
  Future<Uint8List?> read(String id);
  Future<void> delete(String id);
  Future<void> clear();
}
```

### `RealtimeBodyStore` — Per-Session Ring Buffer

**File:** `realtime_body_store.dart`

```dart
class RealtimeBodyStore {
  // Single append-only file per session rotation
  // Frames stored as: [length:4 bytes][data:bytes]
  // Index tracks file offset + rotation count
  
  Future<void> writeFrame(String sessionId, RealtimeFrame frame);
  Future<List<RealtimeFrame>> readFrames(String sessionId, {int? limit});
  Future<void> rotate();  // For testing: force file rotation
  int get currentOffset;
}
```

---

## 3.4 Truncation Logic

**Files:** `body_decode_service.dart`, `raw_capture.dart`, `body_truncation.dart`

### Configuration (InterceptlySettings)

```dart
const InterceptlySettings(
  maxBodyBytes: 5 * 1024 * 1024,      // 5MB hard cap per body
  bodyOffloadThreshold: 50 * 1024,    // 50KB → disk offload
  previewTruncationBytes: 16 * 1024,  // 16KB preview for pending rows
);
```

### `BodyDecodeService.truncate()`

```dart
static Uint8List truncate(Uint8List payload, int maxBodyBytes, int previewBytes) {
  if (maxBodyBytes <= 0) return payload;  // Unlimited
  
  if (payload.length <= maxBodyBytes) return payload;
  
  // Hard truncation at maxBodyBytes
  return payload.sublist(0, maxBodyBytes);
}
```

### `RawCapture.wrapBytes()` — Preview + Storage Truncation

```dart
static TransferableTypedData? wrapBytes(
  Uint8List bytes, 
  [int? maxBytes]  // If null, no truncation
) {
  if (maxBytes != null && bytes.length > maxBytes) {
    // Returns truncated view for storage
    // Original length tracked in responseSizeBytes
    return TransferableTypedData.fromList(bytes.sublist(0, maxBytes));
  }
  return TransferableTypedData.fromList(bytes);
}
```

### Truncation Stages

| Stage | When | Recorded In |
|-------|------|-------------|
| `none` | Body ≤ maxBodyBytes | `BodyTruncation.complete(originalBytes)` |
| `preview` | Pending row, body > previewTruncationBytes | `RequestSummary.requestTruncation` / `responseTruncation` |
| `storage` | Body > maxBodyBytes, excess dropped | `BodyTruncation(stage: storage, originalBytes, retainedBytes)` |

### Response Size Resolution (DefaultHttpTrafficCollector)

```dart
// Priority order for responseSizeBytes:
1. Explicit responseSizeBytes parameter (from Content-Length)
2. Parsed Content-Length header (if ≥ 0)
3. Actual bodyBytes.length

// Truncation decision:
if (responseTruncatedAtStorage != null) {
  isTruncated = responseTruncatedAtStorage;  // Explicit from streaming
} else {
  isTruncated = maxBodyBytes > 0 && 
    (rawLen > maxBodyBytes || 
     (parsedLen != null && parsedLen > maxBodyBytes && rawLen >= maxBodyBytes));
}
```

---

## 3.5 Memory Index — Fast Lookup & Filtering

**File:** `memory_index.dart`

```dart
class MemoryIndex {
  // Ring buffer for entries (O(1) add, O(1) evict)
  final RingBuffer<RequestSummary> _entries;
  
  // Bounded event queue for pending notifications
  final BoundedEventQueue<IndexEvent> _eventQueue;
  
  // Search support
  final MasterSearchController _search;
  
  // Filter support
  RequestFilter _filter;
  
  // Grouping by domain/endpoint
  final GroupingController _grouping;
}
```

### Operations

| Operation | Complexity |
|-----------|------------|
| Add entry | O(1) amortized |
| Evict LRU | O(1) |
| Filter by domain/status/method | O(n) with early exit |
| Search (URL/headers/body) | O(n) with highlights |
| Group by domain | O(n) cached |

---

## 3.6 Network Simulation

**File:** `model/network_simulation.dart`

```dart
class NetworkSimulationProfile {
  final String name;
  final int latencyMs;      // Added to each request
  final int downloadKbps;   // Throttles response chunks
  final int uploadKbps;     // Throttles request chunks
  final bool offline;       // Throws SimulatedNetworkException
}
```

### Application Points

1. **Pre-request** (`HttpTrafficCollector.begin()`): Throws `SimulatedNetworkException` if offline
2. **Request streaming** (`delayForChunk`): Delays request body chunks
3. **Response streaming** (`delayForChunk`): Delays response chunks via `bindResponseStream`
4. **Post-response** (`applyNetworkSimulationAfterResponse`): Additional latency

---

## 3.7 Key Files Quick Reference

| Concept | File |
|---------|------|
| Session singleton | `inspector_session.dart` |
| Isolate bridge | `capture_pipeline.dart`, `writer_isolate.dart` |
| RAM storage | `memory_index.dart`, `ring_buffer.dart`, `bounded_event_queue.dart` |
| Disk storage | `body_store.dart`, `realtime_body_store.dart` |
| Truncation | `body_decode_service.dart`, `raw_capture.dart`, `body_truncation.dart` |
| Simulation | `model/network_simulation.dart` |
| Pending tracking | `pending_tracker.dart` |
| WebSocket storage | `realtime_store.dart` |