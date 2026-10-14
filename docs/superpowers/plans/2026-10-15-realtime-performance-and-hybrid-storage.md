# Clean-Sheet Realtime Architecture: High-Performance Multi-Connection Hybrid Storage Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Completely replace the legacy in-memory Realtime subsystem with a ground-up, clean-sheet architecture featuring zero-allocation ingestion, multi-connection concurrency control, dynamic circular array buffers with a global frame budget, an isolated append-only binary swap store (`_realtime.tmp`), and granular reactive UI rendering without full-tree rebuilds.

**Architecture:**
1. **Clean Ingestion & Normalizer:** Single-pass `FrameNormalizer` with zero-allocation byte calculation (`utf8ByteLength`), 0-copy binary subviews, and handshake-cached capture decisions.
2. **Dedicated Disk Swap Store:** `RealtimeBodyStore` managing an isolated `interceptly_${sessionId}_realtime.tmp` with a FIFO async sequential write queue (eliminating cross-connection write races) and generational rotation fencing.
3. **Multi-Connection Storage Engine:** Complete rewrite of `RealtimeStore` utilizing dynamic circular arrays (16 slots doubling to 1,000 slots per session), global frame budget (5,000 frames) with closed-connection prioritized eviction, and zero-allocation `ListBase` views.
4. **Granular Reactive UI:** Per-connection `ValueNotifier<RealtimeFrameCounts>` for isolated counter updates in `NetworkTab`, collapsed card rendering strictly capped at 128 chars, and on-demand async payload loading with a bounded LRU JSON cache (max 30 items).

**Tech Stack:** Dart 3.6+, Flutter, `dart:io`, `dart:typed_data`, `dart:collection`, `package:test`, `package:flutter_test`.

**Spec:** Clean-Sheet Realtime Subsystem Blueprint (no legacy shims, no deprecated fallbacks).

---

## Global Constraints

- **No Legacy Baggage:** Old `RealtimeStore` ring buffer logic and redundant normalization paths are to be replaced completely.
- **Strict File Isolation:** Realtime disk swap MUST use `interceptly_${sessionId}_realtime.tmp` and NEVER touch or share REST's `_session.tmp`.
- **Zero-Envelope Raw Binary:** Heavy payloads ($\ge 32\text{ KB}$) are written directly as raw bytes without Base64, JSON wrapper, or envelope headers.
- **Zero-Allocation Critical Path:** No throwaway `Uint8List` allocations for text size calculations; no duplicate defensive clones of `Uint8List` payloads.
- **Sequential Disk Writes:** All writes to `RealtimeBodyStore` MUST be serialized via a FIFO async chain to prevent offset corruption across concurrent connections.
- **Zero-Allocation List Reads:** `getRealtimeFrames()` MUST return an unmodifiable `ListBase` view over the circular buffer without calling `.toList()`.
- **Isolated UI Rebuilds:** Ingestion of realtime frames MUST NOT trigger parent `ListView` rebuilds in `NetworkTab`; counter updates MUST use granular `ValueNotifier`s.

---

## Review Focus

1. **Concurrent writes across multiple connections:** Connection A and Connection B simultaneously receive $\ge 32\text{ KB}$ payloads. The async sequential write queue must guarantee offsets never race or corrupt.
2. **File rotation generation fencing:** When `_realtime.tmp` rotates at 50 MB and resets offset to 0, reading an old frame whose `rotationCount` does not match the store's must gracefully return an expired indicator instead of reading corrupt data.
3. **Cross-connection starvation & memory cap:** When 50 connections stream frames and the global cap (5,000 frames) is reached, closed connections (`isClosed == true`) must be evicted before active connections lose frames.
4. **Surrogate pair text truncation:** Multi-byte and emoji payloads truncated at the preview boundary (128 characters) must never split surrogate pairs or generate invalid Unicode.
5. **UI thread isolation during socket bursts:** A burst of 500 frames across 5 connections must not trigger more than one UI notification per 100ms throttle interval and must not rebuild unaffected parent widgets.

---

### Task 1: Dedicated `RealtimeBodyStore` with FIFO Async Sequential Write Queue

**Files:**
- Create: `packages/interceptly/lib/src/session/realtime_body_store.dart`
- Test: `packages/interceptly/test/session/realtime_body_store_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class RealtimeBodyStore {
    Future<void> initForWrite(String dirPath, {String fileName = 'interceptly_realtime.tmp', int maxFileBytes = 50 * 1024 * 1024});
    Future<(int offset, int length, int rotationCount)> append(Uint8List bytes);
    Future<Uint8List> readBytes(int offset, int length);
    Future<void> rotate();
    Future<void> resetFile(String dirPath, {String? fileName});
    Future<void> dispose();
    int get currentOffset;
    int get rotationCount;
    bool get isInitialized;
  }
  ```

- [ ] **Step 1: Write the failing tests for `RealtimeBodyStore`**

Cover:
1. Sequential raw binary appending and exact byte read-back.
2. Concurrency test: 20 simultaneous calls to `append()` without offset races.
3. Automatic rotation when file exceeds `maxFileBytes`, incrementing `rotationCount` and resetting offset to 0.
4. Clean file deletion on `dispose()`.
File: `packages/interceptly/test/session/realtime_body_store_test.dart`.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm dart test test/session/realtime_body_store_test.dart`
Expected: FAIL (file not found).

- [ ] **Step 3: Implement `RealtimeBodyStore`**

Implement sequential FIFO async write queue chaining (`_writeChain = _writeChain.then(...)`), append-only binary writing via `RandomAccessFile`, rotation cap, and isolated read handles.
File: `packages/interceptly/lib/src/session/realtime_body_store.dart`.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm dart test test/session/realtime_body_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/session/realtime_body_store.dart packages/interceptly/test/session/realtime_body_store_test.dart
git commit -m "feat(realtime): add dedicated RealtimeBodyStore with FIFO async sequential queue and rotation fencing"
```

---

### Task 2: Clean-Sheet `RealtimeFrame` Model for Tiered Hybrid Storage & 128-Char Preview

**Files:**
- Modify: `packages/interceptly/lib/src/model/realtime_frame.dart`
- Modify: `packages/interceptly/lib/src/model/interceptly_settings.dart`
- Test: `packages/interceptly/test/session/realtime_session_test.dart`

**Interfaces:**
- Consumes: `BodyLocation` from `body_location.dart`.
- Produces:
  ```dart
  class RealtimeFrame {
    final String id;
    final String sessionId;
    final FrameDirection direction;
    final FrameType type;
    final BodyLocation location;
    final String? textPayload;      // Non-null only when location == BodyLocation.memory && isText
    final Uint8List? binaryPayload; // Non-null only when location == BodyLocation.memory && isBinary
    final String shortPreview;      // Always present in RAM, <= 128 characters, safe Unicode
    final int? fileOffset;          // Non-null when location == BodyLocation.file
    final int? fileLength;          // Non-null when location == BodyLocation.file
    final int? rotationCount;       // Fencing token matching RealtimeBodyStore.rotationCount
    final int payloadSizeBytes;     // Original un-truncated byte size
    final DateTime timestamp;
    final String? eventName;
  }
  ```

- [ ] **Step 1: Write failing unit tests for `RealtimeFrame` hybrid model and preview extractor**

Test:
1. `shortPreview` extraction cuts cleanly at 128 chars without splitting surrogate pairs or emojis.
2. `RealtimeFrame.offloaded` constructor holds `location == BodyLocation.file`, null full payloads, and retains `fileOffset`, `fileLength`, `rotationCount`.
3. `RealtimeFrame.memory` holds inline payloads.
4. Settings carry `realtimeBodyOffloadThreshold` (default 32 KB) and `maxTotalRealtimeFrames` (default 5000).
File: `packages/interceptly/test/session/realtime_session_test.dart`.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm dart test test/session/realtime_session_test.dart`
Expected: FAIL.

- [ ] **Step 3: Refactor `RealtimeFrame` and update `InterceptlySettings`**

1. Rewrite `RealtimeFrame` with clean factory constructors (`.memoryText`, `.memoryBinary`, `.offloaded`).
2. Add static safe `extractShortPreview(dynamic payload, FrameType type, {int maxChars = 128})`.
3. Add `realtimeBodyOffloadThreshold` and `maxTotalRealtimeFrames` to `InterceptlySettings`.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm dart test test/session/realtime_session_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/model/realtime_frame.dart packages/interceptly/lib/src/model/interceptly_settings.dart packages/interceptly/test/session/realtime_session_test.dart
git commit -m "refactor(realtime): update RealtimeFrame model for clean tiered hybrid storage and short preview"
```

---

### Task 3: Zero-Allocation Ingestion Pipeline & Single-Pass Normalizer

**Files:**
- Create: `packages/interceptly/lib/src/capture/frame_normalizer.dart`
- Modify: `packages/interceptly/lib/src/adapter/realtime_session_scope.dart`
- Modify: `packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart`
- Test: `packages/interceptly/test/session/realtime_session_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class NormalizedFrame {
    final FrameType type;
    final dynamic payload; // String or Uint8List
    final int originalSizeBytes;
    final String shortPreview;
    final bool shouldOffload;
  }
  class FrameNormalizer {
    static NormalizedFrame normalize(dynamic raw, {required int offloadThreshold, required int maxBodyBytes});
  }
  ```

- [ ] **Step 1: Write failing tests for single-pass normalization and zero duplicate allocations**

Test:
1. Text payload computes byte size via `utf8ByteLength` with 0 heap byte allocations.
2. Binary payload passed as `Uint8List` or `ByteData` is not cloned via `fromList`.
3. Handshake `shouldCapture` predicate is evaluated once and cached on `RealtimeSessionScope`.
4. Payloads exceeding `offloadThreshold` are marked `shouldOffload = true`.
File: `packages/interceptly/test/session/realtime_session_test.dart`.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm dart test test/session/realtime_session_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `FrameNormalizer` and clean up Scope & Collector**

1. Create `FrameNormalizer` to handle all type detection, 0-alloc byte calculation, preview generation, and offload decision in 1 pass.
2. In `RealtimeSessionScope`: Cache `shouldCapture` boolean check on handshake; delegate to `FrameNormalizer`.
3. In `DefaultRealtimeTrafficCollector`: Remove redundant `Uint8List.fromList` and UTF-16 substring slicing.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm dart test test/session/realtime_session_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/capture/frame_normalizer.dart packages/interceptly/lib/src/adapter/realtime_session_scope.dart packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart packages/interceptly/test/session/realtime_session_test.dart
git commit -m "perf(realtime): add FrameNormalizer with single-pass zero-allocation inspection"
```

---

### Task 4: Clean-Sheet `RealtimeStore`: Dynamic Circular Buffer, Zero-Alloc `ListBase` View & Global Multi-Connection Coordinator

**Files:**
- Modify: `packages/interceptly/lib/src/session/realtime_store.dart`
- Test: `packages/interceptly/test/session/realtime_session_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class RealtimeStore {
    void recordFrame(RealtimeFrame frame);
    List<RealtimeFrame> getRealtimeFrames(String sessionId); // Returns _RealtimeBufferListView
    ValueListenable<RealtimeFrameCounts> getFrameCountsNotifier(String sessionId);
    void markSessionClosed(String sessionId);
    void updateMaxFramesPerSession(int maxFrames);
    void updateGlobalCapacity({int? maxTotalFrames, int? maxSessions});
    void clear();
    void dispose();
  }
  ```

- [ ] **Step 1: Write failing tests for clean `RealtimeStore`**

Test:
1. Dynamic circular buffer: Initial capacity starts at 16 slots, expands exponentially up to `maxFramesPerSession`.
2. Zero-allocation view: `getRealtimeFrames()` returns `ListBase<RealtimeFrame>` that updates in $O(1)$ without allocating new List copies on retrieval.
3. Global budget eviction: With 10 sessions and global cap of 100 frames, frames from closed sessions (`isClosed == true`) are evicted before active sessions lose data.
4. Isolated reactivity: Frame arrival updates only that session's `ValueNotifier<RealtimeFrameCounts>`.
File: `packages/interceptly/test/session/realtime_session_test.dart`.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm dart test test/session/realtime_session_test.dart`
Expected: FAIL.

- [ ] **Step 3: Completely rewrite `RealtimeStore`**

1. Replace `RingBuffer<ListQueue>` with `DynamicCircularBuffer<RealtimeFrame>` backed by a flat `List<RealtimeFrame?>`.
2. Implement `_RealtimeBufferListView extends ListBase<RealtimeFrame>` with modulo index arithmetic.
3. Add `GlobalRealtimeCoordinator` logic tracking total frame count across sessions and prioritizing closed-session eviction.
4. Provide per-session `ValueNotifier<RealtimeFrameCounts>` for localized UI updates.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm dart test test/session/realtime_session_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/session/realtime_store.dart packages/interceptly/test/session/realtime_session_test.dart
git commit -m "refactor(realtime): rewrite RealtimeStore with dynamic circular buffer, zero-alloc ListBase view, and global coordinator"
```

---

### Task 5: Integration of `RealtimeBodyStore` & Async Lazy Load in `InspectorSession`

**Files:**
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart`
- Modify: `packages/interceptly/lib/src/session/inspector_session_view.dart`
- Test: `packages/interceptly/test/session/realtime_session_test.dart`

**Interfaces:**
- Produces:
  ```dart
  abstract interface class InspectorSessionView {
    ...
    Future<dynamic> loadRealtimePayload(RealtimeFrame frame);
    ValueListenable<RealtimeFrameCounts> getRealtimeFrameCountsNotifier(String sessionId);
  }
  ```

- [ ] **Step 1: Write failing tests for end-to-end hybrid storage and lazy load**

Test:
1. Frames $\ge 32\text{ KB}$ are written to `interceptly_${sessionId}_realtime.tmp`, setting `location == BodyLocation.file`.
2. Frames $< 32\text{ KB}$ remain in RAM with `location == BodyLocation.memory`.
3. Calling `session.loadRealtimePayload(frame)` reads back the exact UTF-8 text or raw binary.
4. Expired frame (after file rotation) returns graceful expiration placeholder.
5. `session.clear()` and `session.dispose()` reset/delete `_realtime.tmp` without touching REST's temp file.
File: `packages/interceptly/test/session/realtime_session_test.dart`.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm dart test test/session/realtime_session_test.dart`
Expected: FAIL.

- [ ] **Step 3: Wire `RealtimeBodyStore` in `InspectorSession`**

1. Initialize `RealtimeBodyStore` with `interceptly_${sessionId}_realtime.tmp`.
2. In `recordRealtimeFrame`: If `frame.shouldOffload` and `persistToDisk == true`, append to `RealtimeBodyStore` and store offloaded `RealtimeFrame`.
3. Implement `loadRealtimePayload(RealtimeFrame frame)`.
4. Forward `getRealtimeFrameCountsNotifier` to `_realtimeStore`.
5. Reset and delete `RealtimeBodyStore` during `clear()` and `dispose()`.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm dart test test/session/realtime_session_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/session/inspector_session.dart packages/interceptly/lib/src/session/inspector_session_view.dart packages/interceptly/test/session/realtime_session_test.dart
git commit -m "feat(realtime): integrate RealtimeBodyStore and async lazy load into InspectorSession"
```

---

### Task 6: High-Performance UI Overhaul: Bounded LRU JSON Cache, Short Preview Layout & Localized Badge Rebuilds

**Files:**
- Create: `packages/interceptly/lib/src/ui/detail/realtime/bounded_lru_cache.dart`
- Modify: `packages/interceptly/lib/src/ui/detail/realtime/realtime_payload_view.dart`
- Modify: `packages/interceptly/lib/src/ui/detail/realtime_messages_tab.dart`
- Modify: `packages/interceptly/lib/src/ui/tabs/network_tab.dart`
- Modify: `packages/interceptly/lib/src/ui/tabs/request_log_item.dart`
- Test: `packages/interceptly/test/ui/detail/realtime_messages_tab_test.dart` (or widget tests)

**Interfaces:**
- Consumes: `loadRealtimePayload`, `getRealtimeFrameCountsNotifier` from `InspectorSessionView`.

- [ ] **Step 1: Write failing widget tests for lazy payload loading, bounded LRU JSON cache, and isolated counter rebuild**

Test:
1. Collapsed card displays `shortPreview` without reading disk or parsing JSON.
2. Expanding a file-backed card asynchronously fetches and displays payload.
3. `BoundedLruCache` purges entries beyond capacity 30.
4. Live frame arrivals update only the row's counter badge without rebuilding parent `NetworkTab` list.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/ui/detail/realtime_messages_tab_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement UI rendering optimizations**

1. Create `BoundedLruCache<K, V>` (capacity 30).
2. In `RealtimePayloadView`: Render `frame.shortPreview` on collapsed cards; on inspected cards, fetch payload via `session.loadRealtimePayload`.
3. In `RealtimeMessagesTab`: Replace unbounded map with `BoundedLruCache`.
4. In `NetworkTab` and `RequestLogItem`: Listen to `session.getRealtimeFrameCountsNotifier(entry.id)` via `ValueListenableBuilder` so counter updates do not trigger list rebuilds.

- [ ] **Step 4: Run widget tests to verify they pass**

Run: `fvm flutter test`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/ui/
git commit -m "perf(ui): implement bounded LRU JSON cache, short preview layout, and isolated counter notifiers"
```

---

### Task 7: Multi-Connection Concurrency & Stress Verification Test Suite

**Files:**
- Modify: `packages/interceptly_web_socket/test/stress/websocket_concurrency_stress_test.dart`
- Test: All monorepo packages

**Interfaces:**
- Consumes: All realtime components across packages.

- [ ] **Step 1: Write multi-connection concurrency stress tests**

Simulate:
- 25 concurrent active WebSocket connections.
- 15 closed connections.
- Rapid throughput of 200 msgs/s with mixed sizes (100 B to 200 KB).
- Assertions:
  - Zero offset corruption in `RealtimeBodyStore`.
  - Total frame count strictly capped at `maxTotalRealtimeFrames`.
  - Closed sessions are evicted first under memory pressure.
  - Zero unhandled exceptions or deadlocks.

- [ ] **Step 2: Run concurrency stress test**

Run: `fvm dart test packages/interceptly_web_socket/test/stress/websocket_concurrency_stress_test.dart`
Expected: PASS.

- [ ] **Step 3: Run full monorepo test suite**

Run: `melos run test`
Expected: ALL PASS across `interceptly`, `interceptly_http`, `interceptly_dio`, `interceptly_chopper`, and `interceptly_web_socket`.

- [ ] **Step 4: Commit**

```bash
git add packages/interceptly_web_socket/test/stress/
git commit -m "test(realtime): add comprehensive multi-connection concurrency and stress test suite"
```
