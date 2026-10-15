# Realtime Performance & Architecture Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate hot-path inefficiencies, redundant multi-pass UTF-8 encoding, unthrottled ValueNotifier UI thrashing, per-frame fsync stalls, unbounded write queues, and read-side LRU pollution in Interceptly realtime engine.

**Architecture:**
1. Split `RealtimeStore._getOrCreateBuffer` into read-only access and dirty-LRU touch; replace $O(S)$ global budget scan with $O(1)$ LRU eviction; prevent read operations from mutating session eviction order.
2. Coalesce `ValueNotifier<RealtimeFrameCounts>` updates to the 100ms throttle timer while keeping `getFrameCounts(sessionId)` immediately accurate.
3. Pre-encode UTF-8 bytes once in `FrameNormalizer` for offload-eligible text frames and reuse those bytes directly in `_offloadAndReplaceFrame`.
4. Remove per-frame `_raf!.flush()` in `RealtimeBodyStore` (rely on OS page cache + flush on rotate/close); add bounded write backlog guard; invert `DynamicCircularBuffer.replaceById` scan from head to tail ($O(1)$ hit).
5. Remove double `guardCapture` nesting and redundant `async` microtask in `_WebSocketChannelSender.send`.

**Tech Stack:** Dart 3.x / Flutter, `package:interceptly` Core and `interceptly_web_socket`.

**Spec:** Review findings and performance audit on Interceptly realtime hot-path.

## Global Constraints
- Preserve 100% backward compatibility for all existing SPI and adapter consumers.
- Zero regressions in existing 864 unit, widget, and stress tests.
- Every architectural fix must be clean, maintainable, and built with craftsmanship as if by the original author.

## Review Focus
1. `getRealtimeFrames(sessionId)` must never create empty buffers or re-order `_buffersBySession`.
2. `ValueNotifier<RealtimeFrameCounts>` must fire exactly once per 100ms throttle batch during message storms.
3. Text payload offloaded to disk must have identical bytes to the original string without re-encoding in `_offloadAndReplaceFrame`.
4. Removing `flush()` from `append()` must not corrupt data across reads or file rotations.
5. Inverting `replaceById` search must find the newly appended frame at logical index `count - 1` in $O(1)$.

---

### Task 1: Clean LRU Management, Non-Polluting Reads & O(1) Global Budget Eviction

**Files:**
- Modify: `packages/interceptly/lib/src/session/realtime_store.dart`
- Test: `packages/interceptly/test/session/realtime_session_test.dart`

**Interfaces:**
- `RealtimeStore.getRealtimeFrames(String sessionId) -> List<RealtimeFrame>` (must not alter session LRU order)
- `RealtimeStore.recordFrame(RealtimeFrame frame)` (updates LRU only on session change, $O(1)$ budget eviction)

- [ ] **Step 1: Write failing tests for read-safe LRU and O(1) budget eviction**
Add tests in `packages/interceptly/test/session/realtime_session_test.dart`:
```dart
test('getRealtimeFrames does not pollute or mutate LRU session order', () {
  final store = RealtimeStore(maxFramesPerSession: 10, maxSessions: 3, onThrottledBatch: () {});
  addTearDown(store.dispose);

  // Add frames to s1, s2, s3
  store.recordFrame(RealtimeFrame.text(id: '1', sessionId: 's1', direction: FrameDirection.incoming, text: 'm'));
  store.recordFrame(RealtimeFrame.text(id: '2', sessionId: 's2', direction: FrameDirection.incoming, text: 'm'));
  store.recordFrame(RealtimeFrame.text(id: '3', sessionId: 's3', direction: FrameDirection.incoming, text: 'm'));

  // Read s1 (oldest). Reading s1 MUST NOT make it the MRU.
  store.getRealtimeFrames('s1');

  // Adding s4 should evict s1 (the least recently WRITTEN session)
  store.recordFrame(RealtimeFrame.text(id: '4', sessionId: 's4', direction: FrameDirection.incoming, text: 'm'));

  expect(store.getRealtimeFrames('s1'), isEmpty, reason: 's1 must be evicted because read does not refresh LRU');
  expect(store.getRealtimeFrames('s2').length, equals(1));
  expect(store.getRealtimeFrames('s3').length, equals(1));
  expect(store.getRealtimeFrames('s4').length, equals(1));
});

test('reading non-existent session does not allocate buffer or count towards maxSessions', () {
  final store = RealtimeStore(maxFramesPerSession: 10, maxSessions: 2, onThrottledBatch: () {});
  addTearDown(store.dispose);

  final emptyView = store.getRealtimeFrames('ghost-session');
  expect(emptyView, isEmpty);

  // Now record to s1 and s2
  store.recordFrame(RealtimeFrame.text(id: '1', sessionId: 's1', direction: FrameDirection.incoming, text: 'm'));
  store.recordFrame(RealtimeFrame.text(id: '2', sessionId: 's2', direction: FrameDirection.incoming, text: 'm'));

  // Both s1 and s2 must exist because ghost-session never took a slot
  expect(store.getRealtimeFrames('s1').length, equals(1));
  expect(store.getRealtimeFrames('s2').length, equals(1));
});
```

- [ ] **Step 2: Run test to verify it fails**
Run: `cd packages/interceptly && flutter test test/session/realtime_session_test.dart --name "does not pollute or mutate LRU"`
Expected: FAIL because reading `s1` re-inserts it at the end of the map, causing `s2` to be evicted instead of `s1`.

- [ ] **Step 3: Implement clean LRU separation and non-polluting read in `RealtimeStore`**
1. In `packages/interceptly/lib/src/session/realtime_store.dart`:
   - Keep a `String? _lastActiveSessionId`.
   - In `recordFrame(frame)`:
     If `_lastActiveSessionId != frame.sessionId`:
     - Update LRU order: `_buffersBySession.remove(frame.sessionId); _buffersBySession[frame.sessionId] = buffer;`
     - Set `_lastActiveSessionId = frame.sessionId`.
     - When consecutive frames arrive for the same stream, skip `remove` + `re-insert` completely ($O(1)$ zero-overhead).
   - In `getRealtimeFrames(sessionId)`:
     - Check `_viewsBySession[sessionId]`.
     - If null: check `_buffersBySession[sessionId]`.
     - If buffer exists, create `_RealtimeBufferListView(buffer)` and cache it.
     - If buffer DOES NOT exist, return `_emptyView` (a shared unmodifiable empty view) WITHOUT creating a buffer in `_buffersBySession`.
   - In `_enforceGlobalBudget()`:
     - Prioritize closed sessions using `_closedSessions`.
     - For active sessions, instead of an $O(S)$ linear scan searching for max count, evict from the least recently used session (`_buffersBySession.keys.firstWhere((k) => _buffersBySession[k]!.count > 0)`). This provides true $O(1)$ LRU eviction.

- [ ] **Step 4: Run test to verify it passes**
Run: `cd packages/interceptly && flutter test test/session/realtime_session_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add packages/interceptly/lib/src/session/realtime_store.dart packages/interceptly/test/session/realtime_session_test.dart
git commit -m "perf(realtime): optimize hot-path buffer access, read-safe LRU, and O(1) budget eviction"
```

---

### Task 2: Coalesced `ValueNotifier` Counter Updates to Prevent UI Thrashing

**Files:**
- Modify: `packages/interceptly/lib/src/session/realtime_store.dart`
- Test: `packages/interceptly/test/session/realtime_session_test.dart`

**Interfaces:**
- `getFrameCounts(sessionId)` returns immediate live counts.
- `getFrameCountsNotifier(sessionId)` notifies listeners in coalesced batches matching the 100ms throttle timer.

- [ ] **Step 1: Write failing test for coalesced ValueNotifier updates**
In `packages/interceptly/test/session/realtime_session_test.dart`:
```dart
test('ValueNotifier coalesces frame counts and notifies once per throttle window during message bursts', () {
  fakeAsync((async) {
    final store = RealtimeStore(maxFramesPerSession: 100, onThrottledBatch: () {});
    addTearDown(store.dispose);

    final notifier = store.getFrameCountsNotifier('ws-burst');
    var notifyCount = 0;
    notifier.addListener(() => notifyCount++);

    // Burst 50 frames
    for (var i = 0; i < 50; i++) {
      store.recordFrame(RealtimeFrame.text(
        id: 'f-$i',
        sessionId: 'ws-burst',
        direction: FrameDirection.incoming,
        text: 'msg',
      ));
    }

    // Immediately after burst, getFrameCounts is accurate but notifier has not spammed 50 rebuilds
    expect(store.getFrameCounts('ws-burst').incoming, equals(50));
    expect(notifyCount, equals(0), reason: 'Must not synchronously thrash notifier on every frame');

    // After 100ms throttle window elapses
    async.elapse(const Duration(milliseconds: 100));
    expect(notifyCount, equals(1), reason: 'Must notify exactly once for the burst batch');
    expect(notifier.value.incoming, equals(50));
  });
});
```

- [ ] **Step 2: Run test to verify it fails**
Run: `cd packages/interceptly && flutter test test/session/realtime_session_test.dart --name "coalesces frame counts"`
Expected: FAIL because `notifyCount` is 50 instead of 0 before 100ms.

- [ ] **Step 3: Implement coalesced counter notification in `RealtimeStore`**
1. Track live counts in an internal map `Map<String, RealtimeFrameCounts> _liveCountsBySession = {}`.
2. Track `Set<String> _dirtyNotifierSessions = {}`.
3. In `recordFrame(frame)`:
   - Increment `_liveCountsBySession[frame.sessionId]`.
   - Add `frame.sessionId` to `_dirtyNotifierSessions`.
   - Call `_scheduleNotification()`.
4. In `_scheduleNotification()` callback:
   - Flush `_dirtyNotifierSessions`: for each `sessionId`, update `_notifiersBySession[sessionId]?.value = _liveCountsBySession[sessionId]!`.
   - Clear `_dirtyNotifierSessions`.
   - Invoke `_onThrottledBatch()`.
5. `getFrameCounts(sessionId)` returns `_liveCountsBySession[sessionId] ?? const RealtimeFrameCounts()`.

- [ ] **Step 4: Run test to verify it passes**
Run: `cd packages/interceptly && flutter test test/session/realtime_session_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add packages/interceptly/lib/src/session/realtime_store.dart packages/interceptly/test/session/realtime_session_test.dart
git commit -m "perf(realtime): coalesce ValueNotifier frame count updates to eliminate UI thrashing"
```

---

### Task 3: Single-Pass Pre-Encoded UTF-8 Bytes for Offloaded Frames

**Files:**
- Modify: `packages/interceptly/lib/src/model/realtime_frame.dart`
- Modify: `packages/interceptly/lib/src/capture/frame_normalizer.dart`
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart`
- Test: `packages/interceptly/test/session/realtime_session_test.dart`

**Interfaces:**
- `NormalizedFrame.preEncodedBytes` (Uint8List? pre-encoded bytes when offload is needed)
- `RealtimeFrame.preEncodedBytes` (cached byte buffer avoiding re-encoding in `_offloadAndReplaceFrame`)

- [ ] **Step 1: Write failing test verifying zero re-encode during offload**
In `packages/interceptly/test/session/realtime_session_test.dart`:
```dart
test('FrameNormalizer attaches pre-encoded bytes for frames >= offloadThreshold', () {
  final largeJson = jsonEncode({'data': 'x' * 35000});
  final normalized = FrameNormalizer.normalize(
    largeJson,
    offloadThreshold: 32 * 1024,
    maxBodyBytes: 100 * 1024,
  );
  expect(normalized.shouldOffload, isTrue);
  expect(normalized.preEncodedBytes, isNotNull);
  expect(normalized.preEncodedBytes!.length, equals(normalized.originalSizeBytes));
});
```

- [ ] **Step 2: Run test to verify it fails**
Run: `cd packages/interceptly && flutter test test/session/realtime_session_test.dart --name "attaches pre-encoded bytes"`
Expected: FAIL because `preEncodedBytes` does not exist on `NormalizedFrame`.

- [ ] **Step 3: Implement single-pass encoding in `FrameNormalizer` and `InspectorSession`**
1. In `packages/interceptly/lib/src/capture/frame_normalizer.dart`:
   - Add `final Uint8List? preEncodedBytes;` to `NormalizedFrame`.
   - When text or Map/List payload is processed: if `originalSize >= offloadThreshold && offloadThreshold > 0`:
     - If already encoded to `Uint8List`, reuse it.
     - Otherwise, compute `Uint8List.fromList(utf8.encode(text))` once and assign to `preEncodedBytes`.
2. In `packages/interceptly/lib/src/model/realtime_frame.dart`:
   - Add optional `this.preEncodedBytes` to `RealtimeFrame` (cleared when offloaded to file).
3. In `packages/interceptly/lib/src/session/inspector_session.dart`:
   - In `_offloadAndReplaceFrame(RealtimeFrame frame)`:
     ```dart
     final Uint8List bytes = frame.preEncodedBytes ??
         (frame.type == FrameType.text
             ? Uint8List.fromList(utf8.encode(frame.textPayload ?? ''))
             : frame.binaryPayload ?? Uint8List(0));
     ```
     Zero redundant `utf8.encode()` calls on offloaded frames!

- [ ] **Step 4: Run test to verify it passes**
Run: `cd packages/interceptly && flutter test test/session/realtime_session_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add packages/interceptly/lib/src/model/realtime_frame.dart packages/interceptly/lib/src/capture/frame_normalizer.dart packages/interceptly/lib/src/session/inspector_session.dart packages/interceptly/test/session/realtime_session_test.dart
git commit -m "perf(realtime): single-pass UTF-8 encoding for offloaded realtime frames"
```

---

### Task 4: High-Performance Disk I/O (Remove fsync per frame, Backpressure & Reverse Ring Search)

**Files:**
- Modify: `packages/interceptly/lib/src/session/realtime_body_store.dart`
- Modify: `packages/interceptly/lib/src/session/realtime_store.dart`
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart`
- Test: `packages/interceptly/test/session/realtime_body_store_test.dart`
- Test: `packages/interceptly/test/session/realtime_session_test.dart`

**Interfaces:**
- `RealtimeBodyStore.append`: writes to OS page cache without synchronous `flush()`; flushes on `rotate()` and `close()`.
- `RealtimeBodyStore.pendingWrites`: queue depth for backpressure.
- `DynamicCircularBuffer.replaceById`: reverse search from tail ($O(1)$).

- [ ] **Step 1: Write test for bounded write queue / backpressure and reverse search**
In `packages/interceptly/test/session/realtime_body_store_test.dart`:
```dart
test('append writes sequentially without per-frame flush and flushes on close/rotate', () async {
  final tempDir = await Directory.systemTemp.createTemp('body_store_test');
  addTearDown(() => tempDir.delete(recursive: true));

  final store = RealtimeBodyStore(fileDir: tempDir.path, maxFileBytes: 1024 * 1024);
  await store.initForWrite();
  addTearDown(store.dispose);

  final (offset1, length1, _) = await store.append(Uint8List.fromList([1, 2, 3]));
  final (offset2, length2, _) = await store.append(Uint8List.fromList([4, 5, 6]));

  expect(offset1, equals(0));
  expect(offset2, equals(3));

  final readBack = await store.readBytes(0, 6);
  expect(readBack, equals([1, 2, 3, 4, 5, 6]));
});
```
In `packages/interceptly/test/session/realtime_session_test.dart`:
```dart
test('replaceById in DynamicCircularBuffer finds newest element in reverse search', () {
  final buf = DynamicCircularBuffer(maxCapacity: 100);
  for (var i = 0; i < 50; i++) {
    buf.add(RealtimeFrame.text(id: 'f-$i', sessionId: 's', direction: FrameDirection.incoming, text: 't'));
  }
  final updated = RealtimeFrame.text(id: 'f-49', sessionId: 's', direction: FrameDirection.incoming, text: 'updated');
  expect(buf.replaceById('f-49', updated), isTrue);
  expect(buf[49].textPayload, equals('updated'));
});
```

- [ ] **Step 2: Run test to verify it passes or fails**
Run: `cd packages/interceptly && flutter test test/session/realtime_body_store_test.dart`

- [ ] **Step 3: Implement I/O optimization and backpressure**
1. In `RealtimeBodyStore`:
   - Remove `await _raf!.flush();` in `writeOp`.
   - Call `await _raf!.flush();` in `_performRotate()` and `dispose()`.
   - Maintain `int _pendingWrites = 0`.
   - If `_pendingWrites >= 100`, throw or return fallback error to signal backpressure.
2. In `DynamicCircularBuffer`:
   - Change `replaceById`:
     ```dart
     bool replaceById(String id, RealtimeFrame newFrame) {
       for (var i = _count - 1; i >= 0; i--) {
         final index = (_head + i) % _capacity;
         if (_buffer[index]?.id == id) {
           _buffer[index] = newFrame;
           return true;
         }
       }
       return false;
     }
     ```
3. In `InspectorSession`:
   - In `_offloadAndReplaceFrame`: if `append` throws (e.g. backpressure or I/O error), gracefully leave the frame in memory and log with `debugPrint`, preventing silent unbounded queuing.

- [ ] **Step 4: Run test to verify it passes**
Run: `cd packages/interceptly && flutter test test/session/realtime_body_store_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add packages/interceptly/lib/src/session/realtime_body_store.dart packages/interceptly/lib/src/session/realtime_store.dart packages/interceptly/lib/src/session/inspector_session.dart packages/interceptly/test/session/realtime_body_store_test.dart packages/interceptly/test/session/realtime_session_test.dart
git commit -m "perf(realtime): eliminate per-frame fsync, add backpressure guard, and invert ring buffer search"
```

---

### Task 5: Clean Up Double `guardCapture` & Async Microtask Wrapper

**Files:**
- Modify: `packages/interceptly/lib/src/adapter/realtime_session_scope.dart`
- Modify: `packages/interceptly_web_socket/lib/src/interceptly_web_socket_channel.dart`
- Test: `packages/interceptly/test/adapter/realtime_traffic_collector_test.dart`
- Test: `packages/interceptly_web_socket/test/interceptly_web_socket_channel_test.dart`

**Interfaces:**
- `_WebSocketChannelSender.send`: synchronous call returning `Future.value()`.
- `RealtimeSessionScope`: single-layer guard delegation.

- [ ] **Step 1: Write test verifying exception safety and synchronous execution**
In `packages/interceptly_web_socket/test/interceptly_web_socket_channel_test.dart`:
Verify that `send` immediately invokes `sink.add` synchronously.

- [ ] **Step 2: Implement cleanup**
1. In `packages/interceptly_web_socket/lib/src/interceptly_web_socket_channel.dart`:
   ```dart
   @override
   Future<void> send(RealtimeMessageDraft draft) {
     _channel.sink.add(draft.payload);
     return Future<void>.value();
   }
   ```
2. In `packages/interceptly/lib/src/adapter/realtime_session_scope.dart`:
   - In `send(data, {eventName})`: call `_record(data, FrameDirection.outgoing, eventName: eventName)` directly without redundant `guardCapture` (since `collector.recordFrame` already wraps all logic in `guardCapture`).
   - In `receive(data, {eventName})`: call `_record(data, FrameDirection.incoming, eventName: eventName)` directly.
   - In `close({code, reason})`: call `collector.recordClose` directly without redundant outer `guardCapture`.

- [ ] **Step 3: Run tests to verify all pass**
Run:
```bash
cd packages/interceptly && flutter test test/adapter/realtime_traffic_collector_test.dart
cd packages/interceptly_web_socket && flutter test test/interceptly_web_socket_channel_test.dart
```
Expected: PASS

- [ ] **Step 4: Commit**
```bash
git add packages/interceptly/lib/src/adapter/realtime_session_scope.dart packages/interceptly_web_socket/lib/src/interceptly_web_socket_channel.dart
git commit -m "refactor(realtime): eliminate double guardCapture nesting and unnecessary async microtask"
```

---

### Task 6: Full Monorepo Stress & Integration Verification

**Files:**
- Monorepo full suite

- [ ] **Step 1: Static analysis**
Run: `flutter analyze`
Expected: No issues found!

- [ ] **Step 2: Full test suite & stress tests**
Run:
```bash
cd packages/interceptly && flutter test
cd packages/interceptly_web_socket && flutter test
```
Expected: All tests pass!
