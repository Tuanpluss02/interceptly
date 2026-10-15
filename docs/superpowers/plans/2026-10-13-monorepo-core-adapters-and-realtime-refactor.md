# Monorepo Core-Adapters Split & Realtime Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chuyển đổi `interceptly` thành kiến trúc Monorepo (quản lý bằng Melos) với `interceptly` làm Core độc lập không phụ thuộc thư viện mạng, tách các adapter `dio`, `http`, `chopper` thành các package vệ tinh riêng biệt, và trừu tượng hóa Core Engine để sẵn sàng hỗ trợ Realtime (WebSocket/SSE) với hiệu năng cao.

**Architecture:** Áp dụng Clean Core-Plugin Architecture: Root Monorepo chứa `packages/interceptly` (Core gồm Storage Engine, Isolate, Ring Buffer, UI) có zero third-party network dependencies. Các adapter (`interceptly_dio`, `interceptly_http`, `interceptly_chopper`, `interceptly_web_socket`) là các satellite package cắm vào Core qua `InspectorSession` ingestion contract. Core Engine mở rộng thêm `RealtimeFrame` với Frame Ring Buffer và UI Ticking Batch Throttler (100ms) để chống bão tin nhắn (Message Storm).

**Tech Stack:** Dart 3.5+, Flutter 3.10+, Melos 6.x, `path_provider`, `dio` 5.x, `http` 1.x, `chopper` 8.x, `web_socket_channel` 3.x.

**Spec:** Quyết định kiến trúc của tác giả:
1. `packages/interceptly` là Core duy nhất chứa UI & Engine.
2. Tách hoàn toàn `dio`, `http`, `chopper` thành satellite packages.
3. Trừu tượng hóa Core sẵn sàng cho WebSocket/SSE mà không gây overhead bộ nhớ.

## Global Constraints
- Core `packages/interceptly` tuyệt đối không phụ thuộc vào `dio`, `http`, `chopper` trong `dependencies`.
- Đảm bảo toàn bộ 43 test files hiện tại (đặc biệt 14 stress tests) tiếp tục PASS 100% sau khi di chuyển.
- Giữ nguyên triết lý "Do No Harm": Mọi adapter đều bọc qua `guardCapture` để không bao giờ làm gián đoạn network của host app.
- Realtime frames phải tuân thủ ngân sách bộ nhớ: giới hạn frame per connection qua circular buffer, không lưu trữ vô hạn gây OOM.
- UI Realtime phải có cơ chế throttle (ticking queue ~100ms) để không nghẽn frame rate Flutter (60/120 FPS).

## Review Focus
- **Dependency Isolation**: Core `packages/interceptly/pubspec.yaml` không còn `dio`, `http`, `chopper`.
- **Monorepo Linking**: `melos bootstrap` liên kết chính xác local path dependencies giữa core và adapters.
- **Message Storm Resilience**: Socket bắn 500 frames/giây không làm đứng UI và không rò rỉ RAM vượt quá ngưỡng cấu hình.
- **State Cleanup & Orphan Disposal**: Đóng kết nối WebSocket dọn sạch memory frames tương ứng khi clear session.
- **Backward Usability**: Các test case hiện tại của Dio/Http/Chopper tiếp tục pass trơn tru trên các package vệ tinh mới.

---

### Task 1: Thiết lập cấu trúc Melos Monorepo tại Root

**Files:**
- Create: `melos.yaml`
- Modify: `pubspec.yaml` (root)
- Modify: `.gitignore`

**Interfaces:**
- Produces: Cấu trúc monorepo quản lý thư mục `packages/*` với các script `melos bootstrap`, `melos run test`, `melos run analyze`.

- [ ] **Step 1: Viết cấu hình `melos.yaml` tại thư mục root**
  Cấu hình name `interceptly_monorepo`, packages path `packages/**`, scripts gồm `analyze` (`flutter analyze .`), `test` (`flutter test`).

- [ ] **Step 2: Cập nhật `.gitignore` cho Melos và các thư mục package con**
  Thêm `.melos/`, `.dart_tool/`, `packages/*/.dart_tool/` vào `.gitignore`.

- [ ] **Step 3: Tạo thư mục `packages/` và chuẩn bị di chuyển**
  Chạy lệnh tạo thư mục `mkdir -p packages`.

- [ ] **Step 4: Kiểm tra Melos CLI**
  Chạy `dart pub global activate melos` (nếu chưa có) để kích hoạt Melos trên môi trường phát triển.

- [ ] **Step 5: Commit**
  ```bash
  git add melos.yaml .gitignore
  git commit -m "chore: setup melos monorepo configuration at root"
  ```

---

### Task 2: Chuyển Core `interceptly` vào `packages/interceptly` & Làm sạch Dependencies

**Files:**
- Move: toàn bộ mã nguồn core (`lib/`, `test/`, `android/`, `ios/`, `assets/`, `example/`) vào `packages/interceptly/`
- Modify: `packages/interceptly/pubspec.yaml`
- Modify: `packages/interceptly/lib/interceptly.dart`
- Remove: `packages/interceptly/lib/src/capture/dio/` (tách sang Task 3)
- Remove: `packages/interceptly/lib/src/capture/http/` (tách sang Task 4)
- Remove: `packages/interceptly/lib/src/capture/chopper/` (tách sang Task 5)

**Interfaces:**
- Consumes: Flutter SDK, `path_provider`
- Produces: `package:interceptly` chỉ chứa Core Engine + UI, export `Interceptly`, `InspectorSession`, `RawCapture`, `CaptureGuard`, `InterceptlySettings`.

- [ ] **Step 1: Di chuyển mã nguồn hiện tại vào `packages/interceptly/`**
  Di chuyển an toàn giữ nguyên git history nếu cần hoặc chuyển toàn bộ thư mục.

- [ ] **Step 2: Gọt sạch `pubspec.yaml` của Core**
  Xóa bỏ hoàn toàn:
  ```yaml
  chopper: ^8.6.0
  dio: ^5.10.0
  http: ^1.6.0
  ```
  Giữ lại duy nhất `path_provider` và `flutter`.

- [ ] **Step 3: Cập nhật file barrel `packages/interceptly/lib/interceptly.dart`**
  Bỏ 3 dòng export cũ:
  ```dart
  // XÓA:
  // export 'src/capture/chopper/interceptly_chopper_interceptor.dart';
  // export 'src/capture/dio/interceptly_dio_interceptor.dart';
  // export 'src/capture/http/interceptly_http_client.dart';
  ```
  Thêm export công khai cho `src/capture/capture_guard.dart` để các package vệ tinh tái sử dụng `guardCapture` và `redactHeaders`.

- [ ] **Step 4: Chạy static analysis cho Core**
  Run: `dart analyze packages/interceptly/lib`
  Expected: Không còn compile error nào liên quan tới Dio/Http/Chopper trong Core.

- [ ] **Step 5: Commit**
  ```bash
  git add packages/interceptly
  git commit -m "refactor: migrate core to packages/interceptly and strip network dependencies"
  ```

---

### Task 3: Tạo Package vệ tinh `interceptly_dio`

**Files:**
- Create: `packages/interceptly_dio/pubspec.yaml`
- Create: `packages/interceptly_dio/lib/interceptly_dio.dart`
- Create: `packages/interceptly_dio/lib/src/interceptly_dio_interceptor.dart`
- Create: `packages/interceptly_dio/test/interceptly_dio_interceptor_test.dart`
- Move: Di chuyển các test Dio từ Core sang `packages/interceptly_dio/test/`

**Interfaces:**
- Consumes: `package:interceptly` (Core), `package:dio`
- Produces: `InterceptlyDioInterceptor extends Interceptor`

- [ ] **Step 1: Tạo cấu trúc package `packages/interceptly_dio`**
  Tạo `pubspec.yaml` với dependencies: `flutter`, `dio: '>=5.0.0 <6.0.0'`, `interceptly` (path dependency trong monorepo).

- [ ] **Step 2: Di chuyển `interceptly_dio_interceptor.dart`**
  Đưa code interceptor của Dio từ Core sang `packages/interceptly_dio/lib/src/interceptly_dio_interceptor.dart`, import `package:interceptly/interceptly.dart`.

- [ ] **Step 3: Tạo file barrel `lib/interceptly_dio.dart`**
  Export `src/interceptly_dio_interceptor.dart`.

- [ ] **Step 4: Di chuyển và chạy test của Dio**
  Run: `flutter test packages/interceptly_dio/test`
  Expected: Toàn bộ tests của Dio interceptor PASS.

- [ ] **Step 5: Commit**
  ```bash
  git add packages/interceptly_dio
  git commit -m "feat: create interceptly_dio satellite package"
  ```

---

### Task 4: Tạo Package vệ tinh `interceptly_http`

**Files:**
- Create: `packages/interceptly_http/pubspec.yaml`
- Create: `packages/interceptly_http/lib/interceptly_http.dart`
- Create: `packages/interceptly_http/lib/src/interceptly_http_client.dart`
- Create: `packages/interceptly_http/test/interceptly_http_client_test.dart`
- Move: Di chuyển các test HTTP từ Core sang `packages/interceptly_http/test/`

**Interfaces:**
- Consumes: `package:interceptly` (Core), `package:http`
- Produces: `InterceptlyHttpClient extends http.BaseClient`

- [ ] **Step 1: Tạo cấu trúc package `packages/interceptly_http`**
  Tạo `pubspec.yaml` với dependencies: `flutter`, `http: '>=1.0.0 <2.0.0'`, `interceptly`.

- [ ] **Step 2: Di chuyển `interceptly_http_client.dart`**
  Đưa code `InterceptlyHttpClient` sang `packages/interceptly_http/lib/src/interceptly_http_client.dart`, bao gồm cơ chế Stream Teeing đặc trưng.

- [ ] **Step 3: Tạo file barrel `lib/interceptly_http.dart`**
  Export `src/interceptly_http_client.dart`.

- [ ] **Step 4: Chạy test của Http package**
  Run: `flutter test packages/interceptly_http/test`
  Expected: PASS.

- [ ] **Step 5: Commit**
  ```bash
  git add packages/interceptly_http
  git commit -m "feat: create interceptly_http satellite package"
  ```

---

### Task 5: Tạo Package vệ tinh `interceptly_chopper`

**Files:**
- Create: `packages/interceptly_chopper/pubspec.yaml`
- Create: `packages/interceptly_chopper/lib/interceptly_chopper.dart`
- Create: `packages/interceptly_chopper/lib/src/interceptly_chopper_interceptor.dart`
- Create: `packages/interceptly_chopper/test/interceptly_chopper_interceptor_test.dart`
- Move: Di chuyển các test Chopper từ Core sang `packages/interceptly_chopper/test/`

**Interfaces:**
- Consumes: `package:interceptly` (Core), `package:chopper`
- Produces: `InterceptlyChopperInterceptor`

- [ ] **Step 1: Tạo cấu trúc `packages/interceptly_chopper`**
  Tạo `pubspec.yaml` với dependencies: `flutter`, `chopper: '>=8.0.0 <9.0.0'`, `interceptly`.

- [ ] **Step 2: Di chuyển mã nguồn và test của Chopper**
  Đưa interceptor và các file adversarial test của Chopper sang package mới.

- [ ] **Step 3: Chạy test của Chopper package**
  Run: `flutter test packages/interceptly_chopper/test`
  Expected: PASS.

- [ ] **Step 4: Commit**
  ```bash
  git add packages/interceptly_chopper
  git commit -m "feat: create interceptly_chopper satellite package"
  ```

---

### Task 6: Kiểm tra toàn diện Monorepo với Melos

**Files:**
- Modify: `melos.yaml` (bổ sung scripts nếu cần)

**Interfaces:**
- Produces: Bộ lệnh CI/CD monorepo hoàn chỉnh chạy đồng loạt cho Core và 3 Adapters.

- [ ] **Step 1: Chạy `melos bootstrap` (hoặc lệnh tương đương)**
  Đảm bảo tất cả symlinks giữa `interceptly` và các adapter được thiết lập chuẩn xác.

- [ ] **Step 2: Chạy static analysis toàn bộ monorepo**
  Run: `melos run analyze` (hoặc `dart analyze packages/`)
  Expected: 0 errors, 0 warnings.

- [ ] **Step 3: Chạy toàn bộ test suites của cả 4 packages**
  Run: `melos run test`
  Expected: Toàn bộ unit tests, boundary tests, stress tests đều PASS.

- [ ] **Step 4: Commit**
  ```bash
  git commit --allow-empty -m "test: verify all monorepo packages pass static analysis and test suite"
  ```

---

### Task 7: Trừu tượng hóa Data Model Core cho Realtime

**Files:**
- Create: `packages/interceptly/lib/src/model/realtime_frame.dart`
- Modify: `packages/interceptly/lib/src/model/raw_capture.dart`
- Modify: `packages/interceptly/lib/src/model/index_entry.dart`
- Modify: `packages/interceptly/lib/src/model/interceptly_settings.dart`
- Test: `packages/interceptly/test/model/realtime_frame_test.dart`

**Interfaces:**
- Produces: 
  - `enum FrameDirection { incoming, outgoing }`
  - `enum FrameType { text, binary, ping, pong, close, ack }`
  - `class RealtimeFrame`: Đại diện cho 1 message trong WebSocket/Socket.IO.
  - Thêm cấu hình `maxFramesPerSession` (default: 1000) vào `InterceptlySettings`.

- [ ] **Step 1: Viết test cho `RealtimeFrame`**
  Kiểm tra khởi tạo text frame, binary frame, wrap payload và tính toán byte size.

- [ ] **Step 2: Định nghĩa `RealtimeFrame` trong `realtime_frame.dart`**
  ```dart
  class RealtimeFrame {
    final String id;
    final String sessionId;
    final FrameDirection direction;
    final FrameType type;
    final String? textPayload;
    final Uint8List? binaryPayload;
    final int payloadSizeBytes;
    final DateTime timestamp;
    ...
  }
  ```

- [ ] **Step 3: Bổ sung cài đặt `maxFramesPerSession` vào `InterceptlySettings`**
  Thêm `this.maxFramesPerSession = 1000` để giới hạn số frame tối đa trong RAM cho mỗi kết nối socket.

- [ ] **Step 4: Chạy test xác nhận**
  Run: `flutter test packages/interceptly/test/model/realtime_frame_test.dart`
  Expected: PASS.

- [ ] **Step 5: Commit**
  ```bash
  git add packages/interceptly/lib/src/model/ packages/interceptly/test/model/
  git commit -m "feat(core): add RealtimeFrame data model and settings"
  ```

---

### Task 8: Nâng cấp `InspectorSession` Engine hỗ trợ Realtime & UI Ticking Throttler

**Files:**
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart`
- Modify: `packages/interceptly/lib/src/core/interceptly_controller.dart`
- Test: `packages/interceptly/test/session/realtime_session_test.dart`

**Interfaces:**
- Produces:
  - `InspectorSession.recordRealtimeConnection(...)` (mở kết nối WS)
  - `InspectorSession.recordRealtimeFrame(RealtimeFrame frame)` (ghi nhận frame)
  - `InspectorSession.closeRealtimeConnection(String id)` (đóng kết nối)
  - `List<RealtimeFrame> getFrames(String sessionId)` (truy vấn danh sách frame)
  - Ticking queue: gom frame và phát `notifyListeners()` tối đa 10 lần/giây (100ms) để chống bão tin nhắn.

- [ ] **Step 1: Viết test giả lập Message Storm**
  Bắn 500 frame trong vòng 50ms, kiểm tra:
  1. UI chỉ notify theo nhịp throttle 100ms.
  2. Số lượng frame không vượt quá `maxFramesPerSession` (tự động drop frame cũ theo Ring Buffer).

- [ ] **Step 2: Cài đặt Frame Ring Buffer theo từng Session trong `InspectorSession`**
  Dùng `Map<String, RingBuffer<RealtimeFrame>> _realtimeFramesBySession`.

- [ ] **Step 3: Cài đặt Ticking Throttler**
  Sử dụng Timer định kỳ 100ms: nếu có frame mới trong queue thì flush và `notifyListeners()`. Nếu không có frame mới thì idle.

- [ ] **Step 4: Đảm bảo dọn dẹp khi Clear/Dispose**
  Hàm `clear()` và `dispose()` giải phóng toàn bộ frame buffers và hủy Timer.

- [ ] **Step 5: Chạy test xác nhận**
  Run: `flutter test packages/interceptly/test/session/realtime_session_test.dart`
  Expected: PASS.

- [ ] **Step 6: Commit**
  ```bash
  git add packages/interceptly/lib/src/session/ packages/interceptly/test/session/
  git commit -m "feat(core): implement realtime frame ring buffer and ticking throttler in InspectorSession"
  ```

---

### Task 9: Nâng cấp UI Hiển thị Messages Tab cho WebSocket

**Files:**
- Modify: `packages/interceptly/lib/src/ui/detail/request_detail_page.dart`
- Modify: `packages/interceptly/lib/src/ui/detail/detail_tabs_builder.dart`
- Create: `packages/interceptly/lib/src/ui/detail/realtime_messages_tab.dart`
- Test: `packages/interceptly/test/ui/detail/realtime_messages_tab_test.dart`

**Interfaces:**
- Produces: Tab "Messages" hiển thị danh sách các frame với màu sắc phân biệt chiều In (xanh lá) / Out (xanh dương), lọc theo Text/Binary, thời gian, và ô tìm kiếm nội dung message.

- [ ] **Step 1: Viết widget test cho `RealtimeMessagesTab`**
  Test render danh sách frame, hiển thị payload, badge Direction, và copy payload.

- [ ] **Step 2: Cài đặt `RealtimeMessagesTab`**
  Widget dạng `ListView.builder` ảo hóa, mỗi item hiển thị:
  - Mũi tên chiều: `↓ IN` hoặc `↑ OUT`
  - Thời gian (`HH:mm:ss.SSS`)
  - Loại frame: Text, Binary, Ping/Pong
  - Kích thước bytes
  - Preview payload có hỗ trợ format JSON xem chi tiết.

- [ ] **Step 3: Tích hợp vào `DetailTabsBuilder`**
  Thay thế placeholder `"No WebSocket messages captured"` bằng `RealtimeMessagesTab(sessionId: entry.id)`.

- [ ] **Step 4: Chạy test UI**
  Run: `flutter test packages/interceptly/test/ui/detail/realtime_messages_tab_test.dart`
  Expected: PASS.

- [ ] **Step 5: Commit**
  ```bash
  git add packages/interceptly/lib/src/ui/ packages/interceptly/test/ui/
  git commit -m "feat(ui): implement live realtime messages tab in request detail view"
  ```

---

### Task 10: Xây dựng Package vệ tinh `interceptly_web_socket`

**Files:**
- Create: `packages/interceptly_web_socket/pubspec.yaml`
- Create: `packages/interceptly_web_socket/lib/interceptly_web_socket.dart`
- Create: `packages/interceptly_web_socket/lib/src/interceptly_web_socket_channel.dart`
- Create: `packages/interceptly_web_socket/test/interceptly_web_socket_test.dart`

**Interfaces:**
- Consumes: `package:interceptly` (Core), `package:web_socket_channel`
- Produces: `InterceptlyWebSocketChannel.wrap(WebSocketChannel channel, {Uri? uri})`

- [ ] **Step 1: Viết test cho `InterceptlyWebSocketChannel`**
  Sử dụng fake/mock `WebSocketChannel`, gửi và nhận message, verify `InspectorSession` ghi nhận đúng `RealtimeFrame` incoming và outgoing.

- [ ] **Step 2: Tạo cấu trúc `packages/interceptly_web_socket`**
  `pubspec.yaml` phụ thuộc: `flutter`, `web_socket_channel: '>=3.0.0 <4.0.0'`, `interceptly`.

- [ ] **Step 3: Triển khai `InterceptlyWebSocketChannel`**
  Bọc `channel.stream` (Incoming) bằng StreamTransformer ghi nhận frame. Bọc `channel.sink.add` (Outgoing) để ghi nhận frame trước khi forward vào sink gốc.

- [ ] **Step 4: Chạy test xác nhận**
  Run: `flutter test packages/interceptly_web_socket/test`
  Expected: PASS.

- [ ] **Step 5: Commit**
  ```bash
  git add packages/interceptly_web_socket
  git commit -m "feat: create interceptly_web_socket satellite package"
  ```

---

### Task 11: Stress Test & Khả năng chịu tải Realtime

**Files:**
- Create: `packages/interceptly/test/stress/realtime_message_storm_stress_test.dart`
- Create: `packages/interceptly_web_socket/test/stress/websocket_concurrency_stress_test.dart`

**Interfaces:**
- Produces: Bộ test xác thực hệ thống chịu được tải 10,000 frames/phút mà không rò rỉ RAM hay crash app.

- [ ] **Step 1: Viết `realtime_message_storm_stress_test.dart`**
  Giả lập 10 kết nối WebSocket mở đồng thời, mỗi kết nối bắn 1,000 frames. Kiểm tra:
  - Bộ đệm `maxFramesPerSession` tự động giữ đúng 1,000 frame mới nhất, drop các frame cũ.
  - Bộ nhớ RAM ổn định.
  - Không có exception nào unhandled.

- [ ] **Step 2: Chạy test stress**
  Run: `flutter test packages/interceptly/test/stress/realtime_message_storm_stress_test.dart`
  Expected: PASS trong thời gian quy định.

- [ ] **Step 3: Commit**
  ```bash
  git add packages/interceptly/test/stress/
  git commit -m "test(stress): add realtime message storm and concurrency stress tests"
  ```

---

### Task 12: Hoàn thiện Tài liệu, Example & Kiểm tra Cuối cùng

**Files:**
- Modify: `README.md` (root)
- Modify: `packages/interceptly/README.md`
- Create: `packages/interceptly_dio/README.md`
- Create: `packages/interceptly_web_socket/README.md`
- Modify: `packages/interceptly/example/lib/main.dart`

**Interfaces:**
- Produces: Tài liệu hướng dẫn sử dụng monorepo và ví dụ chạy thử nghiệm cả HTTP lẫn WebSocket.

- [ ] **Step 1: Cập nhật README chính**
  Mô tả cấu trúc Monorepo, hướng dẫn cài đặt Core `interceptly` cùng các adapter `interceptly_dio`, `interceptly_web_socket`.

- [ ] **Step 2: Cập nhật ứng dụng mẫu `example`**
  Demo gửi cả Dio HTTP request và kết nối WebSocket echo để test trực quan trên giao diện.

- [ ] **Step 3: Chạy full test và static analysis toàn bộ monorepo**
  Run: `melos run analyze && melos run test` (hoặc lệnh tương đương)
  Expected: Tất cả 5 packages đều xanh hoàn toàn.

- [ ] **Step 4: Commit**
  ```bash
  git add README.md packages/
  git commit -m "docs: update monorepo documentation and example demo"
  ```
