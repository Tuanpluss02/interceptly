# Separate RealtimeDetailPage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Separate WebSocket/Realtime inspection into a dedicated `RealtimeDetailPage` component, removing all `isRealtime` branching and irrelevant HTTP controls (Replay button, body decoders) from `RequestDetailPage`.

**Architecture:** Create `RealtimeDetailPage` focused purely on streaming connections with 2 tabs (`Messages` first, `Overview` second), socket status badges (`CONNECTED`, `CLOSED`, `DROPPED`), and a live 1s duration ticker. Refactor `RequestDetailPage` and `DetailTabsBuilder` back to pure HTTP/REST inspection, with a backward-compatibility safeguard. Update `NetworkTab` to navigate to the appropriate detail screen based on protocol.

**Tech Stack:** Flutter, Dart, package:test, package:flutter_test

**Spec:** file:///Users/tuanpluss02/.gemini/antigravity/brain/90f92e32-3826-4206-ba5e-90bb7d92e237/realtime_detail_page_spec.md

## Global Constraints

- No external public API breaking changes: `RequestDetailPage` must remain callable and forward realtime entries to `RealtimeDetailPage` if invoked.
- `RealtimeDetailPage` default tab MUST be `Messages` (index 0).
- Replay button MUST NOT exist on `RealtimeDetailPage`.
- Live duration ticker MUST tick second-by-second while connection is active and cancel on close or dispose.
- Static analysis: `flutter analyze` must report 0 issues.
- All 773+ existing tests must continue to pass.

## Review Focus

- Default active tab on opening WebSocket detail is `Messages` (not `Overview`).
- Replay button is completely absent from `RealtimeDetailPage` AppBar.
- Switching to `Overview` tab displays handshake headers, live ticking duration, and frame counts (`↓ X, ↑ Y`).
- Status badge renders `CONNECTED` (green + dot) when active, `CLOSED` on normal closure, `DROPPED` on error/timeout.
- Backward compatibility: Calling `RequestDetailPage` with `entry.isRealtime == true` forwards seamlessly to `RealtimeDetailPage`.

---

### Task 1: Create `RealtimeDetailPage` with Dedicated Tabs and Controls

**Files:**
- Create: `packages/interceptly/lib/src/ui/detail/realtime_detail_page.dart`
- Test: `packages/interceptly/test/ui/detail/realtime_detail_page_test.dart`

**Interfaces:**
- Consumes:
  - `RequestSummary entry` (`packages/interceptly/lib/src/model/request_summary.dart`)
  - `InspectorSessionView session` (`packages/interceptly/lib/src/session/inspector_session_view.dart`)
  - `RealtimeMessagesTab` (`packages/interceptly/lib/src/ui/detail/realtime_messages_tab.dart`)
- Produces:
  - `class RealtimeDetailPage extends StatefulWidget`
    - Constructor: `const RealtimeDetailPage({super.key, required this.entry, required this.session, @visibleForTesting this.nowProvider});`

- [ ] **Step 1: Write the failing widget tests for `RealtimeDetailPage`**

In `packages/interceptly/test/ui/detail/realtime_detail_page_test.dart`:
- Test 1: Defaults to `Messages` tab (finds `RealtimeMessagesTab` or its filter bar, finds no Replay button in AppBar).
- Test 2: Status chip displays `CONNECTED` for active session, `CLOSED` for 1000, and `DROPPED` for 1006.
- Test 3: Switching to `Overview` tab displays URL, Protocol, Handshake Request Headers, and frame statistics (`↓ 8 received, ↑ 3 sent`).
- Test 4: Live duration ticker advances second-by-second with `nowProvider`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/detail/realtime_detail_page_test.dart`
Expected: FAIL (file does not exist or compilation error)

- [ ] **Step 3: Implement `RealtimeDetailPage` in `packages/interceptly/lib/src/ui/detail/realtime_detail_page.dart`**

- Structure:
  - `TabController` with length 2: `[Tab(text: 'Messages'), Tab(text: 'Overview')]`, initial index 0.
  - AppBar: socket path title, status chip (`CONNECTED` with green dot, `CLOSED`, `DROPPED`), back button. NO Replay button.
  - Body: `TabBar` + `TabBarView` (or indexed stack) with:
    - Tab 0: `RealtimeMessagesTab(session: widget.session, sessionId: _currentEntry.id, isConnected: isConnected)`
    - Tab 1: `_buildOverviewTab()` rendering URL, Protocol, Status, Duration, Frame Counts, Handshake Request Headers.
  - Live timer: `_liveTicker` with 1s periodic interval updating duration while connection is open (`statusCode == 0 && !hasError`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/detail/realtime_detail_page_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/ui/detail/realtime_detail_page.dart packages/interceptly/test/ui/detail/realtime_detail_page_test.dart
git commit -m "feat(realtime): add dedicated RealtimeDetailPage with Messages default tab"
```

---

### Task 2: Clean Up `RequestDetailPage` and `DetailTabsBuilder`

**Files:**
- Modify: `packages/interceptly/lib/src/ui/detail/request_detail_page.dart`
- Modify: `packages/interceptly/lib/src/ui/detail/detail_tabs_builder.dart`
- Test: `packages/interceptly/test/ui/detail/request_detail_page_test.dart` (or existing detail tests)

**Interfaces:**
- Consumes:
  - `RealtimeDetailPage` from Task 1 (for backward compatibility forward)
- Produces:
  - Simplified `RequestDetailPage` containing only HTTP/REST logic.
  - Simplified `DetailTabsBuilder` without realtime branches.

- [ ] **Step 1: Write test verifying backward compatibility forwarding in `RequestDetailPage`**

In `packages/interceptly/test/ui/detail/realtime_detail_status_test.dart`:
- Verify that instantiating `RequestDetailPage` with a realtime entry seamlessly renders `RealtimeDetailPage`.

- [ ] **Step 2: Run test to verify current state**

Run: `flutter test test/ui/detail/realtime_detail_status_test.dart`

- [ ] **Step 3: Refactor `RequestDetailPage` and `DetailTabsBuilder`**

- In `request_detail_page.dart`:
  - Add safeguard in `build`: if `widget.entry.isRealtime`, return `RealtimeDetailPage(entry: _currentEntry, session: widget.session, nowProvider: widget.nowProvider)`.
  - Fix `_tabController` to 4 tabs (`Overview`, `Request`, `Response`, `Error`).
  - Remove `isRealtime` checks from `_buildStatusChip`, `computeMatchesAsync`, and tab bars.
  - Remove `_liveTicker` from `RequestDetailPage` (now isolated in `RealtimeDetailPage`).
- In `detail_tabs_builder.dart`:
  - Remove `buildRealtimeMessagesTab()`.
  - Remove `if (record.isRealtime)` from `buildOverviewTab()`.

- [ ] **Step 4: Run tests to verify all detail tests pass**

Run: `flutter test test/ui/detail/`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/ui/detail/request_detail_page.dart packages/interceptly/lib/src/ui/detail/detail_tabs_builder.dart packages/interceptly/test/ui/detail/
git commit -m "refactor(ui): remove realtime branching from RequestDetailPage and DetailTabsBuilder"
```

---

### Task 3: Route `NetworkTab` Navigation & Full Verification

**Files:**
- Modify: `packages/interceptly/lib/src/ui/tabs/network_tab.dart`
- Test: `packages/interceptly/test/ui/tabs/network_tab_protocol_test.dart`

**Interfaces:**
- Consumes:
  - `RealtimeDetailPage` (for `entry.isRealtime`)
  - `RequestDetailPage` (for HTTP requests)

- [ ] **Step 1: Write test in `network_tab_protocol_test.dart` for tap navigation**

- Tap on a REST request -> pushes `RequestDetailPage`.
- Tap on a WebSocket connection -> pushes `RealtimeDetailPage`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/tabs/network_tab_protocol_test.dart -n "opens RealtimeDetailPage"`
Expected: FAIL

- [ ] **Step 3: Update `NetworkTab` navigation in `network_tab.dart`**

In `_buildFlatList` and `_buildGroupedList`:
```dart
onTapNavigate: () => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => req.isRealtime
        ? RealtimeDetailPage(
            entry: req,
            session: widget.session,
            nowProvider: widget.nowProvider,
          )
        : RequestDetailPage(
            entry: req,
            session: widget.session,
            initialQuery: widget.session.masterQuery,
          ),
  ),
),
```

- [ ] **Step 4: Run affected tests**

Run: `flutter test test/ui/tabs/network_tab_protocol_test.dart test/ui/detail/realtime_detail_page_test.dart`
Expected: PASS

- [ ] **Step 5: Run full static analysis and complete test suite**

Run:
```bash
flutter analyze
flutter test
```
Expected: 0 issues, all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/interceptly/lib/src/ui/tabs/network_tab.dart packages/interceptly/test/ui/tabs/network_tab_protocol_test.dart
git commit -m "feat(navigation): route realtime entries to RealtimeDetailPage in NetworkTab"
```
