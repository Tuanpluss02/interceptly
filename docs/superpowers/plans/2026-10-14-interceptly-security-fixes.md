# Interceptly Security Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix WS redaction bypass + export/replay leaks and remove `allowInRelease` entirely, keeping redaction opt-in and disk plaintext-by-design.

**Architecture:** Delete the release-guard surface; route realtime capture through the same `CaptureGuard` path HTTP uses (session settings snapshot at call time); harden share fallback + replay host blocklist. No encryption, no overlay/docs changes.

**Tech Stack:** Flutter/Dart, `flutter test`, Melos monorepo (`packages/interceptly` core).

**Spec:** User decisions 2026-10-14: (1) remove `allowInRelease`, (2) keep `redactedHeaders={}`/`redactedQueryParams={}` opt-in, (3) no disk encryption (binary pack is enough), (4) research+fix WS bypass, (5) fix export/replay, (6) overlay ignored, (7) docs ignored.

## Global Constraints

- Do NOT add inline `#`/`//` comments; docstrings (`///`) only where API needs it.
- Leave all changes uncommitted for user review; do NOT run `git commit/push/merge`.
- Redaction stays opt-in: `InterceptlySettings(redactedHeaders: const {}, redactedQueryParams: const {}, bodyRedactor: null)` unchanged.
- No encryption-at-rest work; no overlay/a11y work; no docs/README work beyond docstrings required by changed signatures.
- Every behavior change needs a failing-then-passing `flutter test`.

## Review Focus

- WS frame with `Authorization` header + `?token=SECRET` URL still stored verbatim after fix; expect `[REDACTED]`.
- `bodyRedactor` that throws or returns null on WS text frame must not drop the connection; expect fallback to original bytes.
- `shouldCapture: (_) => false` must suppress WS connection + frames entirely, not just HTTP.
- Share fallback when `InterceptlyShare.shareFile` returns false must not copy temp file path to clipboard; expect generic toast only.
- Replay of `GET https://192.168.1.1/admin` or `GET https://svc.internal/x` must be blocked like localhost; expect toast + no HTTP call.
- (Covered by Task 1 tests) No symbol named `allowInRelease` remains in `lib/` or `test/`.

---

### Task 1: Remove `allowInRelease` surface

**Files:**
- Modify: `packages/interceptly/lib/src/core/interceptly_controller.dart:20-91`
- Modify: `packages/interceptly/test/interceptly_test.dart:199-210`
- Modify: `packages/interceptly/README.md:379` only if it blocks `dart analyze` (prefer leave; docs out of scope — skip unless test references it)

**Interfaces:**
- Consumes: none
- Produces: `Interceptly({settings, session})`, `Interceptly.init({navigatorKey, showFloatingButton, fabChild, customTrigger, settings, session})`, `Interceptly.instance` bound to `InspectorSession.instance` with no release flag

- [ ] **Step 1: Write failing test for removed API**

```dart
// test/core/no_release_guard_test.dart
test('no allowInRelease symbol in public API', () {
  expect(Interceptly.instance.isEnabled, isNotNull);
});
```

Plus grep assertion run manually: `rg allowInRelease packages/` must return empty after fix.

- [ ] **Step 2: Run to verify current state**

Run: `flutter test test/interceptly_test.dart --plain-name "allowInRelease" -v` in `packages/interceptly`
Expected: PASS today (tests exist) — confirms removal target; after deletion these tests must be deleted.

- [ ] **Step 3: Implement removal in `interceptly_controller.dart`**

Delete constructor param `allowInRelease`, both `assert(!kReleaseMode || ...)` blocks, `instance` hardcode `allowInRelease: true`, `init` param + assert, and release-checklist doc lines mentioning it. Keep `import foundation.dart` only if still used elsewhere in file (`debugPrint`, `kDebugMode`); otherwise remove import.

- [ ] **Step 4: Delete/update `interceptly_test.dart:199-210` allowInRelease tests**

Remove the two tests referencing the param; keep rest of file green.

- [ ] **Step 5: Verify**

Run: `rg allowInRelease packages/ || echo CLEAN` + `flutter test test/interceptly_test.dart -v` in `packages/interceptly`
Expected: CLEAN + PASS

### Task 2: Research WS redaction hook (no code)

**Files:**
- Read: `packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart:46-97`
- Read: `packages/interceptly/lib/src/session/inspector_session.dart:371-400`
- Read: `packages/interceptly/lib/src/capture/capture_guard.dart:44-89`
- Read: `packages/interceptly/lib/src/session/capture_pipeline.dart:122-154`
- Read: `packages/interceptly_web_socket/lib/src/interceptly_web_socket_channel.dart:172-203`

**Interfaces:**
- Consumes: none
- Produces: decision record consumed by Task 3 (where to redact, how to apply `BodyRedactor` to String frames)

- [ ] **Step 1: Answer these and paste conclusions into Task 3 PR description**

```text
1. recordConnection currently calls session.recordRealtimeConnection -> recordPending without CaptureGuard. Fix at collector or session level?
2. recordFrame String payload + bodyRedactor(Uint8List?->Uint8List?): encode utf8 -> redact -> decode with fallback?
3. Binary payload: pass bytes straight to bodyRedactor?
4. shouldCapture(String url): apply to connection URL and skip frames of filtered sessions?
5. DefaultRealtimeTrafficCollector has no settings ref; read session.settings per call — safe under updateSettings?
```

- [ ] **Step 2: Verify no code changed**

Run: `git status --short packages/` in monorepo root
Expected: clean (research only)

### Task 3: Apply redaction + shouldCapture to realtime path

**Files:**
- Modify: `packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart:46-97`
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart:371-400`
- Test: `packages/interceptly/test/session/realtime_redaction_test.dart` (create)

**Interfaces:**
- Consumes: `CaptureGuard.redactHeaders/sanitizeUrl`, `InterceptlySettings.normalizedRedactedHeaders/normalizedRedactedQueryParams/bodyRedactor/shouldCapture`
- Produces: `recordConnection/recordFrame` store redacted values; filtered URLs produce zero entries/frames

- [ ] **Step 1: Write failing tests**

```dart
test('realtime connection redacts headers and query params', () async {
  final session = InspectorSession(settings: InterceptlySettings(
    redactedHeaders: {'authorization'},
    redactedQueryParams: {'token'},
  ));
  session.recordRealtimeConnection(id: 'ws1', url: 'wss://x/?token=SECRET', headers: {'Authorization': 'Bearer S'});
  final entry = session.byId('ws1');
  expect(entry?.requestHeaders['Authorization'], '[REDACTED]');
  expect(entry?.url, isNot(contains('SECRET')));
});

test('realtime frame applies bodyRedactor to text payload', () async {
  final session = InspectorSession(settings: InterceptlySettings(
    bodyRedactor: (b) => null,
  ));
  DefaultRealtimeTrafficCollector(session).recordFrame(
    sessionId: 'ws1', direction: FrameDirection.incoming, type: FrameType.text, payload: '{"password":"x"}');
  expect(session.getRealtimeFrames('ws1'), isNotEmpty);
});

test('shouldCapture false suppresses realtime connection', () async {
  final session = InspectorSession(settings: InterceptlySettings(shouldCapture: (_) => false));
  session.recordRealtimeConnection(id: 'ws-no', url: 'wss://x/', headers: {});
  expect(session.byId('ws-no'), isNull);
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/session/realtime_redaction_test.dart -v` in `packages/interceptly`
Expected: FAIL (headers/URL stored verbatim today)

- [ ] **Step 3: Implement `recordConnection/recordFrame` redaction in `realtime_traffic_collector.dart` + `inspector_session.dart`**

Read `session.settings` per call; `redactHeaders` + `sanitizeUrl` with normalized sets; run text payload through utf8->`bodyRedactor`->utf8 fallback and binary bytes through `bodyRedactor` directly, both inside existing `guardCapture`; early-return when `shouldCapture(url)` is false. Keep `recordClose` unchanged.

- [ ] **Step 4: Verify**

Run: `flutter test test/session/realtime_redaction_test.dart test/session/realtime_session_test.dart test/adapter/traffic_collectors_test.dart -v` in `packages/interceptly`
Expected: PASS

### Task 4: Harden share fallback + default redact on export

**Files:**
- Modify: `packages/interceptly/lib/src/ui/detail/share_handler.dart:17-34,223-252`
- Test: `packages/interceptly/test/export/share_handler_test.dart` (create or extend existing export tests)

**Interfaces:**
- Consumes: `CurlGenerator/HarExporter/PostmanExporter.fromRecord(s, redactOnExport:)`
- Produces: `ShareHandler(redactOnExport: true)` default; share-unavailable path never exposes temp path

- [ ] **Step 1: Write failing tests**

```dart
test('ShareHandler defaults to redactOnExport true', () {
  expect(ShareHandler(context: ctx, fabKey: GlobalKey()).redactOnExport, isTrue);
});
test('share fallback does not copy file path', () async {
  // fake InterceptlyShare returning presented=false; verify Clipboard never receives '.tmp' path
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/export/share_handler_test.dart -v` in `packages/interceptly`
Expected: FAIL (default is false today; fallback copies path at `share_handler.dart:239`)

- [ ] **Step 3: Implement in `share_handler.dart`**

Change both constructors default `redactOnExport` to `true`; in `_shareFile` fallback branch, clipboard + toast must not include `file.path` (generic message only).

- [ ] **Step 4: Verify**

Run: `flutter test test/export/ -v` in `packages/interceptly`
Expected: PASS

### Task 5: Block RFC1918/internal hosts in replay + confirm all methods

**Files:**
- Modify: `packages/interceptly/lib/src/ui/detail/replay_handler.dart:102-116,352-366`
- Test: `packages/interceptly/test/export/export_hardening_test.dart` (extend)

**Interfaces:**
- Consumes: `ReplayHandler.retry(record, confirm:)`, `_isBlockedHost`
- Produces: `_isBlockedHost` true for `10/8, 172.16/12, 192.168/16, .internal, .local`; retry prompts for every method including GET

- [ ] **Step 1: Write failing tests**

```dart
test('replay blocks RFC1918 and .internal hosts', () {
  expect(isBlockedHost('192.168.1.1'), isTrue);
  expect(isBlockedHost('10.0.0.5'), isTrue);
  expect(isBlockedHost('172.16.4.2'), isTrue);
  expect(isBlockedHost('svc.internal'), isTrue);
});
test('retry prompts for GET too', () async {
  // call retry with confirmDialog spy; expect dialog invoked for method GET
});
```

Adjust helper visibility if `_isBlockedHost` is private (expose `@visibleForTesting` static or test via `retry` with fake clientFactory asserting no call).

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/export/export_hardening_test.dart -v` in `packages/interceptly`
Expected: FAIL (hosts pass through today; GET skips confirm per `replay_handler.dart:113`)

- [ ] **Step 3: Implement in `replay_handler.dart`**

Extend `_isBlockedHost` with `10.`, `192.168.`, `172.16-31.`, suffix `.internal`/`.local` (case-insensitive, strip brackets); change `retry` so `shouldPrompt` covers all methods when confirmation UI available (keep `_isNonIdempotent` dialog text but invoke for GET/HEAD too).

- [ ] **Step 4: Verify**

Run: `flutter test test/export/export_hardening_test.dart test/stress/detail_view_and_replay_adversarial_test.dart -v` in `packages/interceptly`
Expected: PASS (adversarial suite is slow; allow extended timeout)

---

## Out of scope (explicitly dropped)

- Redaction defaults stay `{}`/null (Task 0, no change).
- Disk encryption (dropped per binary-pack rationale).
- Overlay show/hide/auth, FAB behavior (dropped).
- README/docs updates (dropped).
