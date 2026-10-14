# Realtime UI Modularization & Auto-Detect Bottom Navigation Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modularize the 660-line WebSocket frame inspector UI into focused components, and add an auto-detecting Bottom Navigation Bar to the main Interceptly screen that cleanly separates REST requests and Realtime WebSocket sessions when realtime capabilities are detected.

**Architecture:** 
1. Extract `realtime_messages_tab.dart` into cohesive subcomponents under `lib/src/ui/detail/realtime/` (formatters, filter header, frame card, payload view) while preserving all test keys and public APIs.
2. Introduce `isRealtimeActive` tracking on `InspectorSession` that triggers automatically upon `RealtimeTrafficCollector` session opening or explicit settings.
3. Enhance `NetworkTab` with protocol-aware filtering (`RequestProtocol.rest`, `RequestProtocol.realtime`, `RequestProtocol.all`).
4. Update `InterceptlyScreen` to conditionally render a themed `NavigationBar` (REST / Realtime) only when `isRealtimeActive` is true, keeping a single-view scaffold when no realtime usage is detected.

**Tech Stack:** Flutter 3.24+, Dart 3.x, Flutter Test

**Spec:** Conversational spec agreed upon in chat (Branch: `refactor/socket-ui-split`).

## Global Constraints

- Flutter SDK >=3.24.0.
- Preserve all existing `ValueKey` IDs (`frame_card_${id}`, `frame_direction_${id}`, `frame_type_${id}`, `frame_size_${id}`, `frame_time_${id}`, `frame_inspect_${id}`, `frame_copy_${id}`, `chip_all`, `chip_incoming`, `chip_outgoing`, `chip_text`, `chip_binary`).
- Zero regressions in existing test suite (`test/ui/detail/realtime_messages_tab_test.dart`).
- When `isRealtimeActive == false`, no `bottomNavigationBar` is rendered in `InterceptlyScreen`, maintaining 100% backward compatibility.
- Re-use `NetworkTab` for both REST and Realtime tabs without duplicating list, grouping, or search infrastructure.

## Review Focus

1. **Test Key Preservation:** All ValueKey identifiers in extracted widgets must match original names exactly so existing widget tests continue to pass.
2. **Realtime Detection Edge Cases:** Calling `session.clear()` must not revert `isRealtimeActive` if the app still has realtime adapter registered or settings enabled.
3. **Tab State Retention:** Switching between REST and Realtime tabs in `InterceptlyScreen` must preserve list scroll position and active search state (via `IndexedStack`).
4. **Empty State Messages:** When on the Realtime tab with 0 socket sessions, the empty view should display an appropriate message (e.g. "No WebSocket connections yet.") rather than generic network text.
5. **Hot Reload / Disposed Safety:** Ensure listeners attached to `session` for realtime detection properly clean up on dispose.

---

### Task 1: Extract Realtime Formatters and Helper Utilities

**Files:**
- Create: `packages/interceptly/lib/src/ui/detail/realtime/realtime_formatters.dart`
- Test: `packages/interceptly/test/ui/detail/realtime/realtime_formatters_test.dart`

**Interfaces:**
- Produces:
  - `String formatFrameTimestamp(DateTime dt)`
  - `String frameTypeLabel(FrameType type)`
  - `String formatBinaryPreview(Uint8List bytes)`
  - `String getFramePayloadString(RealtimeFrame frame)`
  - `dynamic tryParseJsonPayload(RealtimeFrame frame, Map<String, dynamic> cache)`

- [ ] **Step 1: Write unit tests for realtime formatters**

Create `packages/interceptly/test/ui/detail/realtime/realtime_formatters_test.dart` asserting timestamp formatting, type labels (`Text`, `Binary`, `Ping`, `Pong`, `Close`, `Ack`), binary hex preview, and JSON parsing with caching.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/interceptly && flutter test test/ui/detail/realtime/realtime_formatters_test.dart`
Expected: FAIL (file does not exist).

- [ ] **Step 3: Implement `realtime_formatters.dart`**

Extract formatting logic from `realtime_messages_tab.dart` into `packages/interceptly/lib/src/ui/detail/realtime/realtime_formatters.dart`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/interceptly && flutter test test/ui/detail/realtime/realtime_formatters_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/ui/detail/realtime/realtime_formatters.dart packages/interceptly/test/ui/detail/realtime/realtime_formatters_test.dart
git commit -m "refactor(realtime): extract realtime formatters and payload parsers"
```

---

### Task 2: Extract Realtime Filter Header, Payload View, and Frame Card

**Files:**
- Create: `packages/interceptly/lib/src/ui/detail/realtime/realtime_filter_header.dart`
- Create: `packages/interceptly/lib/src/ui/detail/realtime/realtime_payload_view.dart`
- Create: `packages/interceptly/lib/src/ui/detail/realtime/realtime_frame_card.dart`
- Modify: `packages/interceptly/lib/src/ui/detail/realtime_messages_tab.dart`
- Test: `packages/interceptly/test/ui/detail/realtime_messages_tab_test.dart`

**Interfaces:**
- Consumes: `realtime_formatters.dart`
- Produces:
  - `RealtimeFilterHeader(searchController, searchQuery, directionFilter, typeFilter, onSearchChanged, onSearchCleared, onDirectionFilterChanged, onTypeFilterChanged)`
  - `RealtimePayloadView(frame, isInspected, parsedJson, onToggleInspect)`
  - `RealtimeFrameCard(frame, isInspected, parsedJson, onToggleInspect, onCopy)`
  - Refactored `RealtimeMessagesTab` orchestrating the above components.

- [ ] **Step 1: Create `RealtimeFilterHeader` widget**

Extract `_buildFilterHeader` and `_buildFilterChip` into `realtime_filter_header.dart`. Preserve `ValueKey('chip_all')`, `ValueKey('chip_incoming')`, `ValueKey('chip_outgoing')`, `ValueKey('chip_text')`, `ValueKey('chip_binary')`.

- [ ] **Step 2: Create `RealtimePayloadView` and `RealtimeFrameCard` widgets**

Extract payload rendering (JSON viewer vs SelectableText) into `realtime_payload_view.dart` and the frame card (badges, buttons, inspect/copy) into `realtime_frame_card.dart`. Preserve all `ValueKey('frame_card_${frame.id}')`, `ValueKey('frame_direction_${frame.id}')`, `ValueKey('frame_type_${frame.id}')`, `ValueKey('frame_size_${frame.id}')`, `ValueKey('frame_time_${frame.id}')`, `ValueKey('frame_inspect_${frame.id}')`, `ValueKey('frame_copy_${frame.id}')`, `ValueKey('frame_collapse_${frame.id}')`, `ValueKey('frame_payload_${frame.id}')`.

- [ ] **Step 3: Refactor `realtime_messages_tab.dart` to use the subcomponents**

Replace the inline methods in `realtime_messages_tab.dart` with calls to the extracted widgets, reducing the file length from ~660 lines to under 150 lines.

- [ ] **Step 4: Verify existing tests pass**

Run: `cd packages/interceptly && flutter test test/ui/detail/realtime_messages_tab_test.dart`
Expected: PASS (all 7 tests green).

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/ui/detail/realtime/ packages/interceptly/lib/src/ui/detail/realtime_messages_tab.dart
git commit -m "refactor(ui): split RealtimeMessagesTab into modular components"
```

---

### Task 3: Implement Realtime Capability Auto-Detection in Core Session

**Files:**
- Modify: `packages/interceptly/lib/src/model/interceptly_settings.dart:1-120`
- Modify: `packages/interceptly/lib/src/session/inspector_session_view.dart:1-100`
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart:1-450`
- Modify: `packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart:1-120`
- Test: `packages/interceptly/test/session/realtime_autodetect_test.dart`

**Interfaces:**
- Produces:
  - `InterceptlySettings.enableRealtime: bool?`
  - `InspectorSessionView.isRealtimeActive: bool`
  - `InspectorSession.markRealtimeActive(): void`
  - `RealtimeTrafficCollector.markActive(): void`

- [ ] **Step 1: Write failing unit test for realtime auto-detection**

Create `test/session/realtime_autodetect_test.dart`:
- Verify `isRealtimeActive` is `false` initially when no settings and no frames.
- Verify `isRealtimeActive` becomes `true` when `settings.enableRealtime == true`.
- Verify `isRealtimeActive` becomes `true` when `recordRealtimeConnection(...)` is called.
- Verify `isRealtimeActive` becomes `true` when `DefaultRealtimeTrafficCollector.openSession(...)` is called.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/interceptly && flutter test test/session/realtime_autodetect_test.dart`
Expected: FAIL (getter not defined).

- [ ] **Step 3: Implement auto-detection fields & triggers**

1. In `InterceptlySettings`: Add optional `final bool? enableRealtime;` parameter.
2. In `InspectorSessionView`: Add `bool get isRealtimeActive;`.
3. In `InspectorSession`:
   - Add `bool _realtimeExplicitlyEnabled = false;`
   - Implement `isRealtimeActive`: returns `true` if `settings.enableRealtime == true`, or `_realtimeExplicitlyEnabled == true`, or if entries have any WS connection (`entries.any((e) => e.method == 'WS')`).
   - Implement `markRealtimeActive()`: sets `_realtimeExplicitlyEnabled = true` and calls `notifyListeners()`.
   - Call `markRealtimeActive()` inside `recordRealtimeConnection(...)`.
4. In `DefaultRealtimeTrafficCollector`: Call `session.markRealtimeActive()` in `openSession()` and `recordConnection()`. Add static convenience `RealtimeTrafficCollector.markActive()`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/interceptly && flutter test test/session/realtime_autodetect_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/model/interceptly_settings.dart packages/interceptly/lib/src/session/ packages/interceptly/lib/src/adapter/ packages/interceptly/test/session/realtime_autodetect_test.dart
git commit -m "feat(core): auto-detect realtime capability and active adapters"
```

---

### Task 4: Protocol-Aware Filtering in `NetworkTab`

**Files:**
- Create: `packages/interceptly/lib/src/model/network_protocol.dart`
- Export in: `packages/interceptly/lib/interceptly.dart`
- Modify: `packages/interceptly/lib/src/ui/tabs/network_tab.dart`
- Test: `packages/interceptly/test/ui/tabs/network_tab_protocol_test.dart`

**Interfaces:**
- Produces:
  - `enum NetworkProtocol { all, rest, realtime }`
  - `NetworkTab(session, groupingEnabled, onShowFilterPanel, protocol)`

- [ ] **Step 1: Write test for `NetworkTab` protocol filtering**

Create `test/ui/tabs/network_tab_protocol_test.dart`:
- Setup session with 1 GET request and 1 WS connection.
- Verify `NetworkTab(protocol: NetworkProtocol.rest)` shows only the GET request.
- Verify `NetworkTab(protocol: NetworkProtocol.realtime)` shows only the WS connection.
- Verify `NetworkTab(protocol: NetworkProtocol.all)` shows both.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/interceptly && flutter test test/ui/tabs/network_tab_protocol_test.dart`
Expected: FAIL (`NetworkProtocol` not found).

- [ ] **Step 3: Implement `NetworkProtocol` and filtering in `NetworkTab`**

1. Create `packages/interceptly/lib/src/model/network_protocol.dart`:
   ```dart
   enum NetworkProtocol { all, rest, realtime }
   ```
2. In `NetworkTab`: Add `final NetworkProtocol protocol;` (defaults to `NetworkProtocol.all`).
3. In `_buildFlatList` and `_buildGroupedList`:
   Filter `entries` using `protocol`:
   - `NetworkProtocol.rest`: `e.method != 'WS'`
   - `NetworkProtocol.realtime`: `e.method == 'WS'`
   - Adjust empty text: if `protocol == NetworkProtocol.realtime`, display `'No WebSocket connections yet.'`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/interceptly && flutter test test/ui/tabs/network_tab_protocol_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/model/network_protocol.dart packages/interceptly/lib/interceptly.dart packages/interceptly/lib/src/ui/tabs/network_tab.dart packages/interceptly/test/ui/tabs/network_tab_protocol_test.dart
git commit -m "feat(ui): add protocol filtering to NetworkTab (rest, realtime, all)"
```

---

### Task 5: Add Bottom Navigation Bar to `InterceptlyScreen`

**Files:**
- Modify: `packages/interceptly/lib/src/ui/screens/interceptly_screen.dart`
- Test: `packages/interceptly/test/ui/screens/interceptly_screen_bottom_bar_test.dart`

**Interfaces:**
- Consumes: `InspectorSessionView.isRealtimeActive`, `NetworkProtocol`, `NetworkTab`

- [ ] **Step 1: Write failing widget test for `InterceptlyScreen` bottom bar**

Create `test/ui/screens/interceptly_screen_bottom_bar_test.dart`:
- Test A: When `isRealtimeActive == false`, `find.byType(NavigationBar)` is empty.
- Test B: When `isRealtimeActive == true` (e.g. via `settings.enableRealtime: true` or recording WS connection), `find.byType(NavigationBar)` finds 1 widget with 'REST' and 'Realtime' destinations.
- Test C: Tapping destination 1 switches to Realtime tab.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/interceptly && flutter test test/ui/screens/interceptly_screen_bottom_bar_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement bottom bar in `InterceptlyScreen`**

In `_InterceptlyScreenState`:
1. Track `int _selectedTabIndex = 0;`.
2. Check `final isRealtimeActive = widget.session.isRealtimeActive;`.
3. In `Scaffold`:
   - `body`:
     ```dart
     if (!isRealtimeActive)
       NetworkTab(
         session: widget.session,
         protocol: NetworkProtocol.rest,
         groupingEnabled: widget.session.groupingEnabled,
         onShowFilterPanel: () => _showFilterPanel(themedContext),
       )
     else
       IndexedStack(
         index: _selectedTabIndex,
         children: [
           NetworkTab(
             key: const ValueKey('tab_rest'),
             session: widget.session,
             protocol: NetworkProtocol.rest,
             groupingEnabled: widget.session.groupingEnabled,
             onShowFilterPanel: () => _showFilterPanel(themedContext),
           ),
           NetworkTab(
             key: const ValueKey('tab_realtime'),
             session: widget.session,
             protocol: NetworkProtocol.realtime,
             groupingEnabled: widget.session.groupingEnabled,
             onShowFilterPanel: () => _showFilterPanel(themedContext),
           ),
         ],
       )
     ```
   - `bottomNavigationBar`:
     ```dart
     if (isRealtimeActive)
       NavigationBar(
         selectedIndex: _selectedTabIndex,
         onDestinationSelected: (index) => setState(() => _selectedTabIndex = index),
         destinations: const [
           NavigationDestination(
             icon: Icon(Icons.http),
             label: 'REST',
           ),
           NavigationDestination(
             icon: Icon(Icons.cable),
             label: 'Realtime',
           ),
         ],
       )
     ```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/interceptly && flutter test test/ui/screens/interceptly_screen_bottom_bar_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/ui/screens/interceptly_screen.dart packages/interceptly/test/ui/screens/interceptly_screen_bottom_bar_test.dart
git commit -m "feat(ui): add auto-detecting Bottom Navigation Bar in InterceptlyScreen"
```

---

### Task 6: Full Verification & Example App Sanity Check

**Files:**
- All modified files

- [ ] **Step 1: Run static analysis across the package**

Run: `cd packages/interceptly && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Run complete test suite**

Run: `cd packages/interceptly && flutter test`
Expected: All tests pass.

- [ ] **Step 3: Run Example App test to ensure compatibility**

Run: `cd packages/interceptly/example && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Final commit and summary**

```bash
git status
```
Verify working tree is clean.
