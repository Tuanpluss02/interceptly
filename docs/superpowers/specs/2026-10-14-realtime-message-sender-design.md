# Design Spec: Extensible Realtime Message Sender & Protocol Abstraction

**Date:** 2026-10-14  
**Status:** In Review  
**Topic:** Realtime Message Sending (WebSocket, Socket.IO, SSE)  
**Authors:** Antigravity & tuanpluss02  

---

## 1. Context & Motivation

`interceptly` currently supports passive inspection of WebSocket connections via `InterceptlyWebSocketChannel`. While incoming and outgoing frames are captured in `RealtimeStore` and displayed in `RealtimeMessagesTab`, users cannot currently interact with or inject messages into an active connection from within the inspector UI.

In addition, the current implementation hardcodes `method == 'WS'` across several UI and session classes (`NetworkTab`, `RequestDetailPage`, `InspectorSession`). Looking ahead to future adapters such as `interceptly_socket_io` (event-driven, `socket.emit(event, data)`) and `interceptly_sse` (unidirectional, server-to-client only), Interceptly requires a protocol-aware sender abstraction that avoids architectural rewrites when new realtime adapters are added.

### Key Goals
1. **Active Realtime Messaging**: Allow developers/testers to compose and send messages directly through an open connection from the `RealtimeMessagesTab`.
2. **Resend & Edit from History**: Support one-tap "Resend" and "Edit in chat bar" for captured frames in the message timeline.
3. **Protocol Extensibility (WebSocket, Socket.IO, SSE)**: Decouple sender logic from raw WebSockets via `RealtimeConnectionSender` and `RealtimeMessageDraft`, supporting both raw stream payloads (WebSocket) and event-driven emissions (Socket.IO).
4. **Clean Decoupling & Lifecycle Safety**: Ensure that when a connection closes, sending is safely disabled, resources are detached, and attempts to send trigger clear user feedback.

---

## 2. Core Abstractions & Interfaces

### 2.1 Protocol Identification
```dart
/// Supported or planned realtime connection protocols.
enum RealtimeProtocolType {
  /// Raw duplex frame stream (RFC 6455).
  webSocket,

  /// Event-driven bidirectional communication over Engine.IO.
  socketIo,

  /// Unidirectional server-to-client event stream.
  sse,
}
```

### 2.2 Message Draft
```dart
/// Represents a message or event ready to be sent across a realtime connection.
class RealtimeMessageDraft {
  /// The event name (required/primary for Socket.IO, null for raw WebSocket).
  final String? event;

  /// The message payload (String, JSON Map/List, or Uint8List).
  final dynamic payload;

  const RealtimeMessageDraft({
    this.event,
    required this.payload,
  });

  /// Helper to convert payload into a readable text string for editors.
  String get payloadText {
    if (payload is String) return payload as String;
    if (payload == null) return '';
    return payload.toString();
  }
}
```

### 2.3 Sender Delegate Contract
```dart
/// Contract implemented by realtime adapters to handle message transmission.
abstract interface class RealtimeConnectionSender {
  /// The protocol type this sender handles.
  RealtimeProtocolType get protocolType;

  /// Whether sending is currently permitted (e.g. connection is open and writable).
  bool get canSend;

  /// Transmits the given [draft] through the underlying connection sink/client.
  Future<void> send(RealtimeMessageDraft draft);
}
```

---

## 3. Data & Session Layer Changes

### 3.1 Model Updates (`RealtimeFrame`)
- Add `final String? eventName;` to `RealtimeFrame`.
- Update `RealtimeFrame.copyWith`, `==`, `hashCode`, `toString()`, and constructors.
- For WebSocket: `eventName` is `null`.
- For Socket.IO: `eventName` contains the event name (e.g. `'chat_message'`, `'join'`).

### 3.2 Realtime Generalization on `RequestSummary`
- Add `bool get isRealtime => method == 'WS' || method == 'SIO' || method == 'SSE';` on `RequestSummary`.
- Refactor `NetworkTab._filterByProtocol` and `RequestDetailPage` tab selection to check `entry.isRealtime` instead of `entry.method == 'WS'`.

### 3.3 Scope & Collector Enhancements
- **`RealtimeSessionScope`**:
  - Accepts `RealtimeProtocolType protocolType = RealtimeProtocolType.webSocket`.
  - Methods:
    - `void attachSender(RealtimeConnectionSender sender)`
    - `void detachSender()`
    - `bool get canSend => !_isClosed && (_sender?.canSend ?? false);`
    - `Future<void> sendToServer(RealtimeMessageDraft draft)`: invokes `_sender!.send(draft)`.
  - When `scope.close()` is called, `detachSender()` is triggered automatically.
- **`RealtimeTrafficCollector` & `DefaultRealtimeTrafficCollector`**:
  - Maintains `final Map<String, RealtimeSessionScope> _activeScopes = {};`
  - `openSession(...)` accepts `RealtimeProtocolType protocolType` and registers the scope.
  - Exposes:
    - `bool canSend(String sessionId)`
    - `RealtimeConnectionSender? getSender(String sessionId)`
    - `Future<void> sendMessage(String sessionId, RealtimeMessageDraft draft)`
  - `recordClose(sessionId)` removes the scope from `_activeScopes`.
- **`InspectorSessionView` & `InspectorSession`**:
  - Exposes:
    - `bool canSendRealtimeMessage(String sessionId)`
    - `RealtimeProtocolType? getRealtimeProtocol(String sessionId)`
    - `Future<void> sendRealtimeMessage(String sessionId, RealtimeMessageDraft draft)` (delegating to collector).

---

## 4. Adapter Layer: `interceptly_web_socket`

In `InterceptlyWebSocketChannel`:
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
    final data = draft.payload;
    _channel.sink.add(data);
  }
}
```
During initialization:
- Register `_WebSocketChannelSender(this)` with `scope.attachSender(...)`.
- When `sink.add(data)` is executed, the existing `_InterceptlyWebSocketSink` intercepts it and passes it to `scope.send(data)`, automatically recording the outgoing frame into `RealtimeStore` and displaying it on the timeline without duplicate logic.

---

## 5. UI Components & User Experience

### 5.1 Realtime Chat Bar (`realtime_chat_bar.dart`)
Mounted at the bottom of `RealtimeMessagesTab`:
- **State Handling**:
  - Listens to connection status. If `!canSend`, renders a disabled bar showing:
    - *"Connection is closed"* (WebSocket/Socket.IO closed)
    - *"Server-Sent Events is a read-only stream"* (SSE)
- **Protocol-Adaptive Layout**:
  - **WebSocket (`webSocket`)**:
    - Compact 1-line text input (expanding up to 4 lines for multiline text/JSON).
    - Expand button (`Icons.open_in_full`) to open `RealtimeMessageComposerSheet`.
    - Send button (`Icons.send_rounded`, themed `indigo500`).
  - **Socket.IO (`socketIo`)**:
    - Includes an Event Name input field (`[ Event Name ]`) alongside the message payload input.
- **Keybindings / Action**:
  - Pressing Send sends the message, clears the field, and dismisses the keyboard if submitted via keyboard action.
  - Sending catches exceptions and displays a `ToastNotification` on failure.

### 5.2 Expandable Composer Sheet (`realtime_message_composer_sheet.dart`)
Opened via the Expand button in the chat bar:
- Full modal sheet featuring:
  - Header: Protocol title and connection status.
  - Event Name field (visible when `protocolType == RealtimeProtocolType.socketIo`).
  - Multi-line RAW (JSON/Text) text editor with line numbers.
  - "Format JSON" button (auto-indents and validates JSON syntax).
  - Cancel & "Send Message" buttons.

### 5.3 Quick Actions on Message Cards (`realtime_frame_card.dart`)
- **Resend Action**:
  - Added to frame actions.
  - If active: immediately invokes `session.sendRealtimeMessage(frame.sessionId, RealtimeMessageDraft(event: frame.eventName, payload: frame.textPayload ?? frame.binaryPayload))`.
  - If closed: shows Toast `ToastNotification.show('Cannot send: connection is closed')`.
- **Edit Action**:
  - Loads `frame.textPayload` (and `frame.eventName` if present) into the chat bar's controller for modification before sending.
- **Event Badge**:
  - If `frame.eventName != null`, renders a distinct badge `event: <name>` next to direction/type chips.

---

## 6. Testing & Quality Strategy

1. **Unit Tests (Core & Adapters)**:
   - `RealtimeSessionScopeTest`: Verify `attachSender`, `detachSender`, `canSend`, and exception handling.
   - `RealtimeTrafficCollectorTest`: Verify sender registration, session scope tracking, and message routing.
   - `RealtimeFrameTest`: Verify `eventName` serialization, copying, and equality.
   - `InterceptlyWebSocketChannelTest`: Verify that calling `scope.sendToServer(...)` pushes data through the inner sink and records an outgoing frame.
2. **Widget Tests (UI)**:
   - `RealtimeChatBarTest`: Verify rendering under active WebSocket, active Socket.IO (event input visible), and closed states (disabled bar).
   - `RealtimeMessagesTabTest`: Test Resend and Edit actions on `RealtimeFrameCard`.
   - `RealtimeMessageComposerSheetTest`: Verify Format JSON button and draft emission.
3. **Regression Tests**:
   - Ensure existing tests in `test/ui/detail/realtime_messages_tab_test.dart` continue to pass without regression.
