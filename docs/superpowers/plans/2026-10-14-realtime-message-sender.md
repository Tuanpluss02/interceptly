# Realtime Message Sender & Protocol Abstraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement protocol-aware realtime message sending from the Interceptly UI (WebSocket, Socket.IO, SSE), allowing developers to compose, send, resend, and edit messages on active connections.

**Architecture:** 
1. Define protocol abstractions (`RealtimeProtocolType`, `RealtimeMessageDraft`, `RealtimeConnectionSender`) in `interceptly` model/adapter layers and export them in `adapter.dart`.
2. Upgrade `RealtimeFrame` with optional `eventName` and `RequestSummary` with `isRealtime` getter to decouple the UI from hardcoded `'WS'` checks.
3. Wire `RealtimeSessionScope`, `RealtimeTrafficCollector`, and `InspectorSession` with sender registration and message transmission APIs.
4. Hook `_WebSocketChannelSender` into `InterceptlyWebSocketChannel` in `interceptly_web_socket`.
5. Build the protocol-adaptive `RealtimeChatBar`, `RealtimeMessageComposerSheet`, and card quick actions (Resend & Edit) in `RealtimeMessagesTab`.

**Tech Stack:** Flutter 3.24+, Dart 3.x, Flutter Test

**Spec:** [docs/superpowers/specs/2026-10-14-realtime-message-sender-design.md](file:///Users/tuanpluss02/Documents/Boltx/BDS/bds_thm/packages/interceptly/docs/superpowers/specs/2026-10-14-realtime-message-sender-design.md)

## Global Constraints

- Flutter SDK >=3.24.0.
- All new public/exported classes, interfaces, and methods must have docstrings adhering to Dart conventions.
- Maintain 100% backward compatibility for all existing tests in `interceptly` and `interceptly_web_socket`.
- UI ValueKeys must be clear and testable (`realtime_chat_input`, `realtime_chat_send_button`, `realtime_chat_expand_button`, `realtime_chat_event_input`, `frame_resend_${id}`, `frame_edit_${id}`).
- Disabled send UI when `!canSend` (connection closed or read-only protocol like SSE).

## Review Focus

1. **Attempted Send on Closed Connection:** When connection is closed, the UI chat bar must be disabled with a clear message ("Connection is closed"), and invoking `sendMessage` or card Resend must show a descriptive error toast without crashing.
2. **Empty or Whitespace-only Message:** The chat bar Send button should be disabled when the payload input is empty or whitespace-only.
3. **JSON Formatting Error Handling:** In the composer sheet, pressing "Format JSON" on malformed JSON must display an inline warning rather than throwing an exception.
4. **Resend Payload Preservation:** Resending an outgoing frame must preserve its original payload type (`text` vs `binary`) and `eventName` (if set).
5. **Zero Outgoing Capture Duplication:** Sending via `InterceptlyWebSocketChannel` must flow through the existing `_InterceptlyWebSocketSink` so that frames are recorded once through the existing pipeline without double-counting.

---

### Task 1: Core Protocol Abstractions & Model Updates

**Files:**
- Create: `packages/interceptly/lib/src/model/realtime_protocol_type.dart`
- Modify: `packages/interceptly/lib/src/model/realtime_frame.dart`
- Modify: `packages/interceptly/lib/src/model/request_summary.dart`
- Modify: `packages/interceptly/lib/interceptly.dart`
- Modify: `packages/interceptly/lib/adapter.dart`
- Test: `packages/interceptly/test/model/realtime_protocol_type_test.dart`
- Test: `packages/interceptly/test/model/realtime_frame_test.dart`

**Interfaces:**
- Produces:
  - `enum RealtimeProtocolType { webSocket, socketIo, sse }`
  - `class RealtimeMessageDraft { final String? event; final dynamic payload; ... }`
  - `abstract interface class RealtimeConnectionSender { RealtimeProtocolType get protocolType; bool get canSend; Future<void> send(RealtimeMessageDraft draft); }`
  - `RealtimeFrame.eventName` (`String?`)
  - `RequestSummary.isRealtime` (`bool`)

- [ ] **Step 1: Write unit tests for protocol abstractions and updated `RealtimeFrame`**

Create `packages/interceptly/test/model/realtime_protocol_type_test.dart` testing `RealtimeMessageDraft` creation, payload string extraction, equality, and `RealtimeProtocolType` enum values.
Add test cases in `packages/interceptly/test/model/realtime_frame_test.dart` for `eventName`, verifying constructor initialization, `copyWith`, `==`, `hashCode`, and `toString()`.
Add test in `packages/interceptly/test/model/request_summary_test.dart` verifying `isRealtime` is true for `'WS'`, `'SIO'`, `'SSE'`, and false for `'GET'`, `'POST'`, etc.

- [ ] **Step 2: Run tests to verify failure**

Run: `cd packages/interceptly && flutter test test/model/realtime_protocol_type_test.dart`  
Expected: FAIL (types not defined yet).

- [ ] **Step 3: Implement `RealtimeProtocolType`, `RealtimeMessageDraft`, and `RealtimeConnectionSender`**

Create `packages/interceptly/lib/src/model/realtime_protocol_type.dart`:
```dart
enum RealtimeProtocolType {
  webSocket,
  socketIo,
  sse,
}

class RealtimeMessageDraft {
  final String? event;
  final dynamic payload;

  const RealtimeMessageDraft({
    this.event,
    required this.payload,
  });

  String get payloadText {
    if (payload is String) return payload as String;
    if (payload == null) return '';
    return payload.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RealtimeMessageDraft &&
          other.event == event &&
          other.payload == payload;

  @override
  int get hashCode => Object.hash(event, payload);

  @override
  String toString() => 'RealtimeMessageDraft(event: $event, payload: $payload)';
}

abstract interface class RealtimeConnectionSender {
  RealtimeProtocolType get protocolType;
  bool get canSend;
  Future<void> send(RealtimeMessageDraft draft);
}
```

- [ ] **Step 4: Update `RealtimeFrame` and `RequestSummary`**

In `packages/interceptly/lib/src/model/realtime_frame.dart`:
- Add `final String? eventName;` to `RealtimeFrame`.
- Update direct constructor, `.raw`, `.text`, `.binary`, `copyWith`, `==`, `hashCode`, `toString()`.

In `packages/interceptly/lib/src/model/request_summary.dart`:
- Add getter: `bool get isRealtime => method == 'WS' || method == 'SIO' || method == 'SSE';`

Export the new types in `packages/interceptly/lib/interceptly.dart` and `packages/interceptly/lib/adapter.dart`.

- [ ] **Step 5: Run tests to verify pass**

Run: `cd packages/interceptly && flutter test test/model/realtime_protocol_type_test.dart test/model/realtime_frame_test.dart`  
Expected: PASS.

- [ ] **Step 6: Commit Task 1**

```bash
git add packages/interceptly/lib/ packages/interceptly/test/
git commit -m "feat(realtime): add protocol abstraction, message draft, and eventName to RealtimeFrame"
```

---

### Task 2: Decouple Hardcoded `'WS'` Checks across UI & Session

**Files:**
- Modify: `packages/interceptly/lib/src/ui/tabs/network_tab.dart:228-237`
- Modify: `packages/interceptly/lib/src/ui/detail/request_detail_page.dart:88,167,334,466,499,544`
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart:166`
- Test: `packages/interceptly/test/session/realtime_autodetect_test.dart`
- Test: `packages/interceptly/test/ui/tabs/network_tab_test.dart` (if present, or add widget test)

**Interfaces:**
- Consumes: `RequestSummary.isRealtime`
- Produces: Generalized realtime checking for all tabs and detail views without breaking WS.

- [ ] **Step 1: Write failing test for multi-protocol realtime detection**

In `packages/interceptly/test/session/realtime_autodetect_test.dart`, add a test asserting that records with method `'SIO'` or `'SSE'` are properly identified as `isRealtime` and activate realtime UI.

- [ ] **Step 2: Run test to verify failure**

Run: `cd packages/interceptly && flutter test test/session/realtime_autodetect_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Refactor `'WS'` checks to `isRealtime`**

In `network_tab.dart`:
```dart
  List<RequestSummary> _filterByProtocol(List<RequestSummary> list) {
    switch (widget.protocol) {
      case NetworkProtocol.rest:
        return list.where((e) => !e.isRealtime).toList();
      case NetworkProtocol.realtime:
        return list.where((e) => e.isRealtime).toList();
      case NetworkProtocol.all:
        return list;
    }
  }
```

In `request_detail_page.dart`:
Replace `_currentEntry.method == 'WS'` and `widget.entry.method == 'WS'` with `entry.isRealtime`.

In `inspector_session.dart`:
Update `isRealtimeActive`:
```dart
_memoryIndex.entries.any((e) => e.isRealtime);
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd packages/interceptly && flutter test test/session/realtime_autodetect_test.dart`  
Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```bash
git add packages/interceptly/lib/ packages/interceptly/test/
git commit -m "refactor(realtime): generalize realtime protocol checks using entry.isRealtime"
```

---

### Task 3: Pluggable Sender Infrastructure in Scope, Collector & Session

**Files:**
- Modify: `packages/interceptly/lib/src/adapter/realtime_session_scope.dart`
- Modify: `packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart`
- Modify: `packages/interceptly/lib/src/session/inspector_session_view.dart`
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart`
- Test: `packages/interceptly/test/adapter/realtime_traffic_collector_test.dart`
- Test: `packages/interceptly/test/session/realtime_session_test.dart`

**Interfaces:**
- Consumes: `RealtimeConnectionSender`, `RealtimeMessageDraft`, `RealtimeProtocolType`
- Produces:
  - `RealtimeSessionScope.attachSender(RealtimeConnectionSender sender)`
  - `RealtimeSessionScope.detachSender()`
  - `RealtimeSessionScope.canSend` (`bool`)
  - `RealtimeSessionScope.sendToServer(RealtimeMessageDraft draft)`
  - `RealtimeTrafficCollector.canSend(String sessionId)` (`bool`)
  - `RealtimeTrafficCollector.getSender(String sessionId)` (`RealtimeConnectionSender?`)
  - `RealtimeTrafficCollector.sendMessage(String sessionId, RealtimeMessageDraft draft)` (`Future<void>`)
  - `InspectorSessionView.canSendRealtimeMessage(String sessionId)` (`bool`)
  - `InspectorSessionView.getRealtimeProtocol(String sessionId)` (`RealtimeProtocolType?`)
  - `InspectorSessionView.sendRealtimeMessage(String sessionId, RealtimeMessageDraft draft)` (`Future<void>`)

- [ ] **Step 1: Write unit tests for scope sender attachment, collector routing, and session delegation**

Create/update `packages/interceptly/test/adapter/realtime_traffic_collector_test.dart`:
- Test attaching a fake `RealtimeConnectionSender` to `RealtimeSessionScope`.
- Test `scope.canSend` reflects `!isClosed && sender.canSend`.
- Test `scope.close()` detaches sender.
- Test `collector.sendMessage(...)` routes draft to sender.
- Test `collector.sendMessage(...)` on closed/unknown session throws `StateError` or returns gracefully with error.
- Test `InspectorSession.sendRealtimeMessage` delegates to collector.

- [ ] **Step 2: Run test to verify failure**

Run: `cd packages/interceptly && flutter test test/adapter/realtime_traffic_collector_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Update `RealtimeSessionScope`**

In `packages/interceptly/lib/src/adapter/realtime_session_scope.dart`:
- Add `final RealtimeProtocolType protocolType;` (defaults to `RealtimeProtocolType.webSocket`).
- Add `RealtimeConnectionSender? _sender;`
- Add:
```dart
  void attachSender(RealtimeConnectionSender sender) {
    if (_isClosed) return;
    _sender = sender;
  }

  void detachSender() {
    _sender = null;
  }

  bool get canSend => !_isClosed && (_sender?.canSend ?? false);

  RealtimeConnectionSender? get sender => _sender;

  Future<void> sendToServer(RealtimeMessageDraft draft) async {
    if (!canSend || _sender == null) {
      throw StateError('Cannot send message: connection is closed or sender unavailable');
    }
    await _sender!.send(draft);
  }
```
- In `close()`, call `detachSender()`.

- [ ] **Step 4: Update `RealtimeTrafficCollector` & `DefaultRealtimeTrafficCollector`**

In `packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart`:
- Update `openSession` signature:
```dart
  RealtimeSessionScope openSession({
    Uri? uri,
    String? sessionId,
    Map<String, String>? headers,
    RealtimeProtocolType protocolType = RealtimeProtocolType.webSocket,
  });
  bool canSend(String sessionId);
  RealtimeConnectionSender? getSender(String sessionId);
  Future<void> sendMessage(String sessionId, RealtimeMessageDraft draft);
```
- In `DefaultRealtimeTrafficCollector`:
  - Track `final Map<String, RealtimeSessionScope> _activeScopes = {};`
  - In `openSession`, store scope in `_activeScopes[effectiveId]`.
  - In `recordClose(sessionId: ...)`, remove `_activeScopes.remove(sessionId)`.
  - Implement `canSend(sessionId)`: returns `_activeScopes[sessionId]?.canSend ?? false`.
  - Implement `getSender(sessionId)`: returns `_activeScopes[sessionId]?.sender`.
  - Implement `sendMessage(sessionId, draft)`: calls `_activeScopes[sessionId]!.sendToServer(draft)`.

- [ ] **Step 5: Expose APIs on `InspectorSessionView` & `InspectorSession`**

In `packages/interceptly/lib/src/session/inspector_session_view.dart`:
```dart
  bool canSendRealtimeMessage(String sessionId) => false;
  RealtimeProtocolType? getRealtimeProtocol(String sessionId) => null;
  Future<void> sendRealtimeMessage(String sessionId, RealtimeMessageDraft draft) async {}
```
In `packages/interceptly/lib/src/session/inspector_session.dart`:
- Delegate `canSendRealtimeMessage`, `getRealtimeProtocol`, and `sendRealtimeMessage` to `RealtimeTrafficCollector.instance`.

- [ ] **Step 6: Run tests to verify pass**

Run: `cd packages/interceptly && flutter test test/adapter/realtime_traffic_collector_test.dart test/session/realtime_session_test.dart`  
Expected: PASS.

- [ ] **Step 7: Commit Task 3**

```bash
git add packages/interceptly/lib/ packages/interceptly/test/
git commit -m "feat(realtime): wire sender registration and message transmission into scope and collector"
```

---

### Task 4: Implement WebSocket Sender in `interceptly_web_socket`

**Files:**
- Modify: `packages/interceptly_web_socket/lib/src/interceptly_web_socket_channel.dart`
- Test: `packages/interceptly_web_socket/test/interceptly_web_socket_channel_test.dart`

**Interfaces:**
- Consumes: `RealtimeSessionScope.attachSender`, `RealtimeConnectionSender`, `RealtimeMessageDraft`, `RealtimeProtocolType.webSocket`
- Produces: Live socket transmission from Interceptly UI through wrapped `WebSocketChannel`.

- [ ] **Step 1: Write unit tests for `InterceptlyWebSocketChannel` sending from scope**

In `packages/interceptly_web_socket/test/interceptly_web_socket_channel_test.dart`:
- Test that after connecting, `channel.scope.canSend` is `true`.
- Test that calling `channel.scope.sendToServer(RealtimeMessageDraft(payload: 'Hello from UI'))` invokes `inner.sink.add('Hello from UI')`.
- Test that the sent frame is captured as an `outgoing` frame in `RealtimeTrafficCollector`.
- Test that after closing the channel, `channel.scope.canSend` is `false`, and sending throws a `StateError`.

- [ ] **Step 2: Run test to verify failure**

Run: `cd packages/interceptly_web_socket && flutter test test/interceptly_web_socket_channel_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Implement sender in `InterceptlyWebSocketChannel`**

In `packages/interceptly_web_socket/lib/src/interceptly_web_socket_channel.dart`:
- Define `_WebSocketChannelSender`:
```dart
class _WebSocketChannelSender implements RealtimeConnectionSender {
  final InterceptlyWebSocketChannel _channel;
  _WebSocketChannelSender(this._channel);

  @override
  RealtimeProtocolType get protocolType => RealtimeProtocolType.webSocket;

  @override
  bool get canSend => !_channel.scope.isClosed;

  @override
  Future<void> send(RealtimeMessageDraft draft) async {
    _channel.sink.add(draft.payload);
  }
}
```
- In `InterceptlyWebSocketChannel` constructor:
```dart
scope.attachSender(_WebSocketChannelSender(this));
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd packages/interceptly_web_socket && flutter test test/interceptly_web_socket_channel_test.dart`  
Expected: PASS.

- [ ] **Step 5: Commit Task 4**

```bash
git add packages/interceptly_web_socket/
git commit -m "feat(web_socket): implement RealtimeConnectionSender in InterceptlyWebSocketChannel"
```

---

### Task 5: Adaptive Chat Bar & Composer Sheet Components

**Files:**
- Create: `packages/interceptly/lib/src/ui/detail/realtime/realtime_chat_bar.dart`
- Create: `packages/interceptly/lib/src/ui/detail/realtime/realtime_message_composer_sheet.dart`
- Test: `packages/interceptly/test/ui/detail/realtime/realtime_chat_bar_test.dart`
- Test: `packages/interceptly/test/ui/detail/realtime/realtime_message_composer_sheet_test.dart`

**Interfaces:**
- Produces:
  - `RealtimeChatBar`:
    ```dart
    class RealtimeChatBar extends StatefulWidget {
      final String sessionId;
      final InspectorSessionView? session;
      final TextEditingController textController;
      final TextEditingController? eventController;
      final VoidCallback onSend;
      final VoidCallback onExpand;
      ...
    }
    ```
  - `RealtimeMessageComposerSheet`:
    ```dart
    class RealtimeMessageComposerSheet extends StatefulWidget {
      final RealtimeProtocolType protocolType;
      final String initialEvent;
      final String initialPayload;
      final Future<void> Function(RealtimeMessageDraft draft) onSend;
      ...
    }
    ```

- [ ] **Step 1: Write widget tests for `RealtimeChatBar`**

Create `packages/interceptly/test/ui/detail/realtime/realtime_chat_bar_test.dart`:
- Test active WebSocket mode: renders single payload field with `key: const ValueKey('realtime_chat_input')` and Send button `key: const ValueKey('realtime_chat_send_button')`. Event input is NOT present.
- Test active Socket.IO mode: renders Event input `key: const ValueKey('realtime_chat_event_input')` AND payload field.
- Test closed connection mode: input is disabled and notice "Connection is closed" is rendered. Send button is disabled.
- Test typing text enables Send button; tapping Send triggers `onSend`.
- Test tapping Expand button `key: const ValueKey('realtime_chat_expand_button')` triggers `onExpand`.

- [ ] **Step 2: Run test to verify failure**

Run: `cd packages/interceptly && flutter test test/ui/detail/realtime/realtime_chat_bar_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Implement `RealtimeChatBar`**

Create `packages/interceptly/lib/src/ui/detail/realtime/realtime_chat_bar.dart` with InterceptlyTheme styling, subtle borders, disabled banner when `!canSend`, compact horizontal layout, expandable lines (1-4 lines), and themed buttons.

- [ ] **Step 4: Write widget tests for `RealtimeMessageComposerSheet`**

Create `packages/interceptly/test/ui/detail/realtime/realtime_message_composer_sheet_test.dart`:
- Test opening sheet with initial text and JSON.
- Test tapping "Format JSON" formats valid JSON with indentation.
- Test tapping "Format JSON" with invalid JSON displays inline warning without crashing.
- Test tapping Send sends `RealtimeMessageDraft` and pops sheet.

- [ ] **Step 5: Implement `RealtimeMessageComposerSheet`**

Create `packages/interceptly/lib/src/ui/detail/realtime/realtime_message_composer_sheet.dart` with header, optional Event Name field (if Socket.IO), JSON syntax highlighter, line numbers, Format JSON action, and themed Send button.

- [ ] **Step 6: Run tests to verify pass**

Run: `cd packages/interceptly && flutter test test/ui/detail/realtime/realtime_chat_bar_test.dart test/ui/detail/realtime/realtime_message_composer_sheet_test.dart`  
Expected: PASS.

- [ ] **Step 7: Commit Task 5**

```bash
git add packages/interceptly/lib/src/ui/detail/realtime/ packages/interceptly/test/ui/detail/realtime/
git commit -m "feat(ui): add protocol-adaptive RealtimeChatBar and RealtimeMessageComposerSheet"
```

---

### Task 6: Wire Message Sending, Resend, and Edit into `RealtimeMessagesTab` & Frame Cards

**Files:**
- Modify: `packages/interceptly/lib/src/ui/detail/realtime/realtime_frame_card.dart`
- Modify: `packages/interceptly/lib/src/ui/detail/realtime_messages_tab.dart`
- Test: `packages/interceptly/test/ui/detail/realtime_messages_tab_test.dart`

**Interfaces:**
- Consumes: `RealtimeChatBar`, `RealtimeMessageComposerSheet`, `InspectorSessionView.sendRealtimeMessage`, `RealtimeFrame.eventName`
- Produces: Integrated realtime message inspection and transmission UI.

- [ ] **Step 1: Write widget tests for Resend and Edit actions on frame cards**

In `packages/interceptly/test/ui/detail/realtime_messages_tab_test.dart`:
- Test that each frame card has a "Resend" button (`key: ValueKey('frame_resend_${frame.id}')`) and "Edit" button (`key: ValueKey('frame_edit_${frame.id}')`).
- Test that tapping "Edit" populates the `RealtimeChatBar` payload field with `frame.textPayload`.
- Test that tapping "Resend" on an active connection sends the frame payload.
- Test that tapping "Resend" on a closed connection shows a toast warning without crashing.
- Test that if `frame.eventName != null`, the event badge is rendered on the card.

- [ ] **Step 2: Run test to verify failure**

Run: `cd packages/interceptly && flutter test test/ui/detail/realtime_messages_tab_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Update `RealtimeFrameCard`**

In `packages/interceptly/lib/src/ui/detail/realtime/realtime_frame_card.dart`:
- Add `final VoidCallback? onResend;` and `final VoidCallback? onEdit;` callbacks.
- Add an Event badge chip next to the Direction and Type badges if `frame.eventName != null`.
- Add Resend icon button (`Icons.replay_rounded`) and Edit icon button (`Icons.edit_note_rounded`) to the action buttons row.

- [ ] **Step 4: Update `RealtimeMessagesTab`**

In `packages/interceptly/lib/src/ui/detail/realtime_messages_tab.dart`:
- Add controllers for chat bar text and event name.
- Mount `RealtimeChatBar` at the bottom of the column (below the frame list).
- Implement `_sendMessage`:
  - Validates payload is non-empty.
  - Constructs `RealtimeMessageDraft`.
  - Calls `widget.session?.sendRealtimeMessage(...)`.
  - Handles errors with `ToastNotification`.
- Implement `_onEditFrame(RealtimeFrame frame)`:
  - Fills controllers and focuses input.
- Implement `_onResendFrame(RealtimeFrame frame)`:
  - Directly sends draft. If connection is closed, shows Toast: `"Cannot send: connection is closed"`.
- Implement `_onExpandComposer`:
  - Shows `RealtimeMessageComposerSheet` in modal bottom sheet.

- [ ] **Step 5: Run tests to verify pass**

Run: `cd packages/interceptly && flutter test test/ui/detail/realtime_messages_tab_test.dart`  
Expected: PASS.

- [ ] **Step 6: Commit Task 6**

```bash
git add packages/interceptly/lib/ packages/interceptly/test/
git commit -m "feat(ui): integrate RealtimeChatBar, Resend, and Edit actions into RealtimeMessagesTab"
```

---

### Task 7: Full Monorepo Static Analysis & Test Verification

**Files:**
- Entire repository

- [ ] **Step 1: Run static analysis across monorepo**

Run: `dart analyze` or `flutter analyze` across packages:
```bash
cd packages/interceptly && flutter analyze
cd ../interceptly_web_socket && flutter analyze
```
Expected: 0 errors, 0 warnings.

- [ ] **Step 2: Run full test suite across packages**

Run:
```bash
cd packages/interceptly && flutter test
cd ../interceptly_web_socket && flutter test
```
Expected: ALL PASS.

- [ ] **Step 3: Commit final verification**

```bash
git commit --allow-empty -m "chore: verify static analysis and test suite across realtime sender changes"
```
