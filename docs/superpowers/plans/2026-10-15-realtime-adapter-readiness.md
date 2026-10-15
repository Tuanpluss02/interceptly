# Realtime Adapter Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enhance Interceptly Core SPI and Session Ingestion to fully support diverse realtime adapters (Socket.IO, SSE, MQTT) with event name propagation, protocol type mapping in connection entries, and automatic JSON serialization for structured payloads.

**Architecture:** Extend `RealtimeSessionScope` and `RealtimeTrafficCollector` to pass optional `eventName` metadata down to `RealtimeFrame`; propagate `RealtimeProtocolType` during handshake to record correct HTTP/Realtime method codes (`WS`, `SIO`, `SSE`) in `InspectorSession`; and upgrade `FrameNormalizer` to serialize Dart `Map` and `List` objects into canonical JSON.

**Tech Stack:** Dart 3.x / Flutter, `package:interceptly` SPI (`adapter.dart`).

**Spec:** Architectural audit of Interceptly realtime subsystem for third-party adapter readiness.

## Global Constraints

- Preserve complete backward compatibility for existing `InterceptlyWebSocketChannel` and REST adapters.
- Zero crashes on malformed data via `guardCapture` and non-throwing fallbacks in `FrameNormalizer`.
- Zero unnecessary allocations: maintain zero-copy views and O(1) ring buffer semantics.
- Every modification must be verified with automated unit tests using `flutter test`.

## Review Focus

1. `eventName` is safely optional and defaults to `null` so WebSocket frames without events suffer zero overhead.
2. `protocolType` maps accurately to `WS` (WebSocket), `SIO` (Socket.IO), and `SSE` (Server-Sent Events) in pending/index entries.
3. Non-encodable objects in `FrameNormalizer` (e.g. cyclic references or non-JSON classes) gracefully fall back to `raw.toString()` without crashing.
4. `session.recordRealtimeConnection` preserves custom timestamps and headers across all protocol types.
5. `RealtimeSessionScope.send` and `receive` remain fully non-blocking and safe when connection is closed.

---

### Task 1: Event Name Propagation in Realtime Session Scope & Collector

**Files:**
- Modify: `packages/interceptly/lib/src/adapter/realtime_session_scope.dart`
- Modify: `packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart`
- Test: `packages/interceptly/test/adapter/realtime_traffic_collector_test.dart`

**Interfaces:**
- Produces:
  - `RealtimeSessionScope.send(dynamic data, {String? eventName})`
  - `RealtimeSessionScope.receive(dynamic data, {String? eventName})`
  - `RealtimeTrafficCollector.recordFrame({..., String? eventName})`
  - `DefaultRealtimeTrafficCollector.recordFrame({..., String? eventName})`

- [ ] **Step 1: Write the failing test for eventName recording**

Add a test group to `packages/interceptly/test/adapter/realtime_traffic_collector_test.dart`:
```dart
test('scope.send and scope.receive propagate eventName to recorded frames', () {
  final scope = collector.openSession(sessionId: 's-events');
  scope.send('hello event', eventName: 'chat_message');
  scope.receive('ack event', eventName: 'chat_ack');

  final frames = session.getRealtimeFrames('s-events');
  expect(frames.length, equals(2));
  expect(frames[0].direction, equals(FrameDirection.outgoing));
  expect(frames[0].eventName, equals('chat_message'));
  expect(frames[0].textPayload, equals('hello event'));

  expect(frames[1].direction, equals(FrameDirection.incoming));
  expect(frames[1].eventName, equals('chat_ack'));
  expect(frames[1].textPayload, equals('ack event'));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/interceptly && flutter test test/adapter/realtime_traffic_collector_test.dart`
Expected: Compilation error or failure because `send` / `receive` / `recordFrame` do not accept `eventName`.

- [ ] **Step 3: Implement eventName parameter in `RealtimeSessionScope` and `RealtimeTrafficCollector`**

1. In `packages/interceptly/lib/src/adapter/realtime_session_scope.dart`:
   - Update `send(dynamic data, {String? eventName})` to forward `eventName` to `_record(data, FrameDirection.outgoing, eventName: eventName)`.
   - Update `receive(dynamic data, {String? eventName})` to forward `eventName` to `_record(data, FrameDirection.incoming, eventName: eventName)`.
   - In `_record`, pass `eventName: eventName` to `collector.recordFrame(...)`.
2. In `packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart`:
   - Add `String? eventName` to `RealtimeTrafficCollector.recordFrame`.
   - In `DefaultRealtimeTrafficCollector.recordFrame`: accept `String? eventName` and pass it to `RealtimeFrame(..., eventName: eventName)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/interceptly && flutter test test/adapter/realtime_traffic_collector_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/adapter/realtime_session_scope.dart packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart packages/interceptly/test/adapter/realtime_traffic_collector_test.dart
git commit -m "feat(realtime): propagate eventName through session scope and traffic collector"
```

---

### Task 2: Protocol Type Mapping in Connection Handshake (`recordRealtimeConnection`)

**Files:**
- Modify: `packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart`
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart`
- Test: `packages/interceptly/test/session/realtime_autodetect_test.dart`

**Interfaces:**
- Consumes: `RealtimeProtocolType`
- Produces:
  - `RealtimeTrafficCollector.recordConnection({..., RealtimeProtocolType protocolType = RealtimeProtocolType.webSocket})`
  - `InspectorSession.recordRealtimeConnection({..., RealtimeProtocolType protocolType = RealtimeProtocolType.webSocket})`
  - Method mappings: `webSocket` -> `'WS'`, `socketIo` -> `'SIO'`, `sse` -> `'SSE'`

- [ ] **Step 1: Write the failing test for protocolType connection recording**

Add test to `packages/interceptly/test/session/realtime_autodetect_test.dart`:
```dart
test('recordRealtimeConnection maps protocolType to correct method (WS, SIO, SSE)', () {
  final collector = DefaultRealtimeTrafficCollector(session: session);

  collector.openSession(
    sessionId: 'conn_ws',
    uri: Uri.parse('wss://example.com/ws'),
    protocolType: RealtimeProtocolType.webSocket,
  );
  collector.openSession(
    sessionId: 'conn_sio',
    uri: Uri.parse('https://example.com/socket.io'),
    protocolType: RealtimeProtocolType.socketIo,
  );
  collector.openSession(
    sessionId: 'conn_sse',
    uri: Uri.parse('https://example.com/events'),
    protocolType: RealtimeProtocolType.sse,
  );

  expect(session.byId('conn_ws')?.method, equals('WS'));
  expect(session.byId('conn_ws')?.isRealtime, isTrue);

  expect(session.byId('conn_sio')?.method, equals('SIO'));
  expect(session.byId('conn_sio')?.isRealtime, isTrue);

  expect(session.byId('conn_sse')?.method, equals('SSE'));
  expect(session.byId('conn_sse')?.isRealtime, isTrue);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/interceptly && flutter test test/session/realtime_autodetect_test.dart`
Expected: FAIL because `conn_sio` and `conn_sse` have method `'WS'`.

- [ ] **Step 3: Implement protocolType propagation and method mapping**

1. In `packages/interceptly/lib/src/session/inspector_session.dart`:
   - In `recordRealtimeConnection`, add `RealtimeProtocolType protocolType = RealtimeProtocolType.webSocket`.
   - Compute method:
     ```dart
     final method = switch (protocolType) {
       RealtimeProtocolType.webSocket => 'WS',
       RealtimeProtocolType.socketIo => 'SIO',
       RealtimeProtocolType.sse => 'SSE',
     };
     ```
   - Pass `method: method` into `_recordPendingEntry`.
2. In `packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart`:
   - In `RealtimeTrafficCollector.recordConnection`: add `RealtimeProtocolType protocolType = RealtimeProtocolType.webSocket`.
   - In `DefaultRealtimeTrafficCollector.openSession`: pass `protocolType: protocolType` to `session.recordRealtimeConnection(...)`.
   - In `DefaultRealtimeTrafficCollector.recordConnection`: pass `protocolType: protocolType` to `session.recordRealtimeConnection(...)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/interceptly && flutter test test/session/realtime_autodetect_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart packages/interceptly/lib/src/session/inspector_session.dart packages/interceptly/test/session/realtime_autodetect_test.dart
git commit -m "feat(realtime): map protocolType to WS, SIO, and SSE in connection entries"
```

---

### Task 3: Automatic JSON Normalization for Structured Payloads in `FrameNormalizer`

**Files:**
- Modify: `packages/interceptly/lib/src/capture/frame_normalizer.dart`
- Test: `packages/interceptly/test/session/realtime_session_test.dart`

**Interfaces:**
- Consumes: `dynamic raw` payload in `FrameNormalizer.normalize`
- Produces: Canonical JSON string payload for `Map` and `List` objects, safe fallback to `toString()` for unencodable types.

- [ ] **Step 1: Write the failing tests for Map and List normalization**

Add tests to `packages/interceptly/test/session/realtime_session_test.dart` in `group('FrameNormalizer & Ingestion Pipeline')`:
```dart
test('normalizes Map payload into canonical JSON text frame with accurate byte size', () {
  final payload = {'event': 'message', 'data': {'userId': 42, 'active': true}};
  final normalized = FrameNormalizer.normalize(
    payload,
    offloadThreshold: 32 * 1024,
    maxBodyBytes: 1024,
  );
  expect(normalized.type, equals(FrameType.text));
  expect(normalized.payload, equals('{"event":"message","data":{"userId":42,"active":true}}'));
  expect(normalized.originalSizeBytes, equals(utf8.encode(normalized.payload as String).length));
  expect(normalized.shortPreview, contains('{"event":"message"'));
});

test('normalizes List payload into canonical JSON array text frame', () {
  final payload = ['chat_message', {'text': 'hi'}];
  final normalized = FrameNormalizer.normalize(
    payload,
    offloadThreshold: 32 * 1024,
    maxBodyBytes: 1024,
  );
  expect(normalized.type, equals(FrameType.text));
  expect(normalized.payload, equals('["chat_message",{"text":"hi"}]'));
});

test('falls back gracefully to toString() if Map/List contains circular reference or fails to encode', () {
  final cyclicList = <dynamic>[];
  cyclicList.add(cyclicList); // cyclic reference
  final normalized = FrameNormalizer.normalize(
    cyclicList,
    offloadThreshold: 32 * 1024,
    maxBodyBytes: 1024,
  );
  expect(normalized.type, equals(FrameType.text));
  expect(normalized.payload, contains('[...]'));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/interceptly && flutter test test/session/realtime_session_test.dart`
Expected: FAIL because Map currently formats as `{event: message, ...}` instead of valid JSON string.

- [ ] **Step 3: Implement JSON serialization in `FrameNormalizer`**

In `packages/interceptly/lib/src/capture/frame_normalizer.dart`:
- Import `dart:convert`.
- When `raw is Map || raw is List`:
  ```dart
  String text;
  try {
    text = jsonEncode(raw);
  } catch (_) {
    text = raw.toString();
  }
  ```
- Process `text` with `utf8ByteLength(text)`, truncation against `maxBodyBytes`, and `extractShortPreview(text, type)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/interceptly && flutter test test/session/realtime_session_test.dart`
Expected: PASS

- [ ] **Step 5: Run full test suite across interceptly**

Run: `cd packages/interceptly && flutter test`
Expected: All tests pass without warnings or errors.

- [ ] **Step 6: Commit**

```bash
git add packages/interceptly/lib/src/capture/frame_normalizer.dart packages/interceptly/test/session/realtime_session_test.dart
git commit -m "feat(realtime): support automatic JSON serialization for Map and List frame payloads"
```

---

### Task 4: Full Monorepo Verification & Sanity Check

**Files:**
- Test: all packages in monorepo

- [ ] **Step 1: Run static analysis across monorepo**
Run: `flutter analyze`
Expected: No issues found!

- [ ] **Step 2: Run test suite across monorepo**
Run:
```bash
flutter test packages/interceptly/test
flutter test packages/interceptly_web_socket/test
```
Expected: All tests pass!
