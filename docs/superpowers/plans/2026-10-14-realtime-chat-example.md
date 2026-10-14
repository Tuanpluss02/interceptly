# Realtime Support Chat Example Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the minimal WebSocket echo example in the Interceptly example app into a realistic, interactive **Customer Support Chat** application powered by a smart mock agent bot ("Sarah") on `ExampleLocalServer` and a dedicated `ExampleChatPage` UI.

---

## File Structure

- **Modify**: `packages/interceptly/example/lib/src/example_local_server.dart`
  - Add `/ws/chat` WebSocket endpoint.
  - Implement system welcome, agent greeting, typing indicators, and contextual responses (ping/pong, bug report guidance, general inquiries).
  - Provide connection heartbeat.
- **Create**: `packages/interceptly/example/lib/src/example_chat_page.dart`
  - Stateful chat screen with Sarah avatar, connection status, quick prompt chips, message bubbles, and Interceptly Inspector shortcut.
- **Modify**: `packages/interceptly/example/lib/src/example_home_page.dart`
  - Update "Realtime WebSocket Traffic" section with a modern Live Chat demo card, navigation to `ExampleChatPage`, and quick test action.
- **Modify**: `packages/interceptly/example/lib/src/example_request_runner.dart`
  - Update `runWebSocketEcho` or add `runWebSocketChatSimulation` to test the new chat flow.
- **Create**: `packages/interceptly/example/test/example_chat_page_test.dart`
  - Widget tests for `ExampleChatPage` rendering, message sending, and quick prompts.

---

### Task 1: Server-Side Support Chat Bot in `ExampleLocalServer`

**Files:**
- Modify: `packages/interceptly/example/lib/src/example_local_server.dart`
- Create: `packages/interceptly/example/test/example_chat_server_test.dart`

- [ ] **Step 1: Write unit test for `/ws/chat` endpoint**

In `packages/interceptly/example/test/example_chat_server_test.dart`:
- Start `ExampleLocalServer`.
- Connect to `/ws/chat` via `WebSocket.connect`.
- Verify receipt of initial `system` welcome message and `agent_message` from "Sarah".
- Send `{"type": "chat", "message": "ping"}` and verify receipt of pong response.
- Close server and socket.

- [ ] **Step 2: Run test to verify failure**

Run: `cd packages/interceptly/example && flutter test test/example_chat_server_test.dart`  
Expected: FAIL (endpoint `/ws/chat` not handled yet).

- [ ] **Step 3: Implement `/ws/chat` in `ExampleLocalServer`**

In `packages/interceptly/example/lib/src/example_local_server.dart`:
- Match `path == '/ws/chat' && WebSocketTransformer.isUpgradeRequest(request)`.
- On connection upgrade:
  - Send welcome message:
    ```json
    {
      "type": "system",
      "event": "connected",
      "message": "Kết nối thành công đến Support Hub. Nhân viên hỗ trợ Sarah đã sẵn sàng!"
    }
    ```
  - Schedule agent greeting after 400ms:
    ```json
    {
      "type": "agent_message",
      "from": "Sarah (Support Specialist)",
      "message": "Xin chào! Mình là Sarah từ bộ phận hỗ trợ Interceptly. Bạn cần mình hỗ trợ gì hôm nay?"
    }
    ```
  - On incoming messages:
    - Send typing notification: `{"type": "typing", "from": "Sarah", "status": true}`.
    - After 300ms, reply contextually based on content:
      - Contains "lỗi" / "bug" / "error": *"Bạn có thể mở Interceptly Inspector để kiểm tra frame payload và status code chi tiết nhé!"*
      - Contains "ping": *"Pong! 🏓 Độ trễ WebSocket ổn định."*
      - Default: *"Cảm ơn bạn đã nhắn tin! Sarah đã ghi nhận: '[message]'."*

- [ ] **Step 4: Run test to verify pass**

Run: `cd packages/interceptly/example && flutter test test/example_chat_server_test.dart`  
Expected: PASS.

- [ ] **Step 5: Commit Task 1**

```bash
git add packages/interceptly/example/
git commit -m "feat(example): add realistic /ws/chat support agent bot to local server"
```

---

### Task 2: Build `ExampleChatPage`

**Files:**
- Create: `packages/interceptly/example/lib/src/example_chat_page.dart`
- Create: `packages/interceptly/example/test/example_chat_page_test.dart`

- [ ] **Step 1: Write widget tests for `ExampleChatPage`**

In `packages/interceptly/example/test/example_chat_page_test.dart`:
- Test that `ExampleChatPage` renders AppBar with "Sarah (Support Specialist)", connection status chip, and "Inspect" button.
- Test quick action chips: "Ping test", "Báo lỗi hệ thống", "Kiểm tra đơn hàng".
- Test typing message into input and tapping Send adds user message bubble.
- Test tapping "Inspect" calls `Interceptly.show()`.

- [ ] **Step 2: Run test to verify failure**

Run: `cd packages/interceptly/example && flutter test test/example_chat_page_test.dart`  
Expected: FAIL (`ExampleChatPage` does not exist).

- [ ] **Step 3: Implement `ExampleChatPage`**

In `packages/interceptly/example/lib/src/example_chat_page.dart`:
- Models: `ChatMessage(id, text, from, isMe, isSystem, timestamp)`.
- Connects using `InterceptlyWebSocketChannel.connect(wsUri)` so all frames flow into Interceptly inspector.
- Listens to incoming stream and parses JSON:
  - System messages (`type: "system"`).
  - Agent messages (`type: "agent_message"`).
  - Typing indicators (`type: "typing"`).
- UI Components:
  - Custom AppBar with avatar and connection status.
  - Interceptly guide banner.
  - Chat bubble ListView with auto-scroll to bottom.
  - Typing indicator animation when Sarah is typing.
  - Quick action chips row above input.
  - TextField + Send IconButton.
  - Proper resource disposal on `dispose()`.

- [ ] **Step 4: Run test to verify pass**

Run: `cd packages/interceptly/example && flutter test test/example_chat_page_test.dart`  
Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```bash
git add packages/interceptly/example/
git commit -m "feat(example): create realistic ExampleChatPage with live bot interaction"
```

---

### Task 3: Integrate Chat Demo into `ExampleHomePage`

**Files:**
- Modify: `packages/interceptly/example/lib/src/example_home_page.dart`
- Modify: `packages/interceptly/example/lib/src/example_request_runner.dart`

- [ ] **Step 1: Update `example_request_runner.dart`**

Update `runWebSocketEcho` to use `/ws/chat`, verify receipt of welcome & agent messages, and document the flow.

- [ ] **Step 2: Update `ExampleHomePage` UI**

In `packages/interceptly/example/lib/src/example_home_page.dart`:
- Redesign "Realtime WebSocket Traffic" section:
  - Title: "Realtime WebSocket: Live Support Chat"
  - Subtitle: "Experience a live customer support chat channel with real-time bidirectional messaging, typing indicators, and full inspection."
  - Primary button: **"Mở Live Support Chat"** (navigates to `ExampleChatPage`).
  - Secondary button: **"Test nhanh (Quick Run)"** (executes `_runner.runWebSocketEcho`).

- [ ] **Step 3: Run existing example tests**

Run: `cd packages/interceptly/example && flutter test`  
Expected: PASS.

- [ ] **Step 4: Commit Task 3**

```bash
git add packages/interceptly/example/
git commit -m "feat(example): integrate Live Support Chat into ExampleHomePage"
```

---

### Task 4: Monorepo Verification & Static Analysis

**Files:**
- Entire repository

- [ ] **Step 1: Analyze and test `example`**

Run:
```bash
cd packages/interceptly/example
flutter analyze
flutter test
```

- [ ] **Step 2: Verify `packages/interceptly` and `packages/interceptly_web_socket`**

Run:
```bash
cd packages/interceptly
flutter test test/ui/detail/realtime/
flutter analyze
```

- [ ] **Step 3: Commit any final polishing**
