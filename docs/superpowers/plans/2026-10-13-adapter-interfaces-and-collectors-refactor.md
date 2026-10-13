# Adapter Interfaces & Traffic Collectors Refactoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chuẩn hóa kiến trúc các adapter vệ tinh bằng cách xây dựng hệ thống Interface & Collector Delegation chuẩn (`HttpTrafficCollector`, `RealtimeTrafficCollector`, `HttpCaptureAdapter`, `RealtimeCaptureAdapter`) trong Core, loại bỏ hoàn toàn code trùng lặp và cách làm "mệnh ai nấy quyết" hiện tại.

**Architecture:** Áp dụng Bridge & SPI Pattern. Core định nghĩa các contract (`HttpTrafficCollector`, `RealtimeTrafficCollector`) cùng implementation mặc định (`DefaultHttpTrafficCollector`, `DefaultRealtimeTrafficCollector`) chịu trách nhiệm tập trung về timing, guard an toàn, mô phỏng mạng, và lưu trữ session. Các satellite adapter (`interceptly_dio`, `interceptly_http`, `interceptly_chopper`, `interceptly_web_socket`) sẽ implement các interface định danh (`HttpCaptureAdapter`, `RealtimeCaptureAdapter`) và ủy quyền toàn bộ logic điều phối capture cho Collector.

**Tech Stack:** Dart 3.5+, Flutter 3.10+, Melos Monorepo, Dio 5.x, http 1.x, Chopper 8.x, web_socket_channel 2.x/3.x.

**Spec:** Đề xuất tái cấu trúc chuẩn hóa Adapter SPI trong cuộc đối thoại ngày 2026-10-13.

## Global Constraints

- Dart SDK: `>=3.5.0 <4.0.0`, Flutter: `>=3.10.0`.
- 100% mã nguồn phân tích tĩnh đạt 0 warnings, 0 errors qua `melos run analyze`.
- Toàn bộ test suites hiện tại (hơn 550 tests) phải giữ nguyên tính đúng đắn và PASS 100% qua `melos run test`.
- Tương thích ngược: API công khai của các satellite adapter (`InterceptlyDioInterceptor`, `InterceptlyHttpClient`, `InterceptlyChopperInterceptor`, `InterceptlyWebSocketChannel`) không bị phá vỡ (non-breaking change đối với end-users).
- Làm việc tại: `/Users/tuanpluss02/Documents/Boltx/BDS/bds_thm/packages/interceptly`.

## Review Focus

- Không có rò rỉ ngoại lệ: Collector phải đảm bảo mọi thao tác capture nội bộ đều được bọc an toàn (`guardCapture`), không bao giờ làm crash luồng mạng của ứng dụng.
- Pre-request và post-response simulation (`applyNetworkSimulationBeforeRequest`, `applyNetworkSimulationAfterResponse`) phải được thực thi nhất quán trên tất cả adapter.
- Stream-teeing trong `interceptly_http` phải giữ nguyên tính toàn vẹn single-subscription của `StreamedResponse`.
- WebSocket frame serialization không được làm sai lệch dữ liệu payload nhị phân hoặc chuỗi UTF-8.
- Cấu hình custom `InspectorSession` hoặc `Interceptly` instance phải truyền xuyên suốt qua Collector.

---

### Task 1: Xây dựng Core SPI & Traffic Collectors trong `packages/interceptly`

**Files:**
- Create: `packages/interceptly/lib/src/adapter/http_request_context.dart`
- Create: `packages/interceptly/lib/src/adapter/http_traffic_collector.dart`
- Create: `packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart`
- Create: `packages/interceptly/lib/src/adapter/network_capture_adapter.dart`
- Modify: `packages/interceptly/lib/interceptly.dart`
- Create: `packages/interceptly/test/adapter/traffic_collectors_test.dart`

**Interfaces:**
- Produces:
  - `class HttpRequestContext`: lưu giữ `id`, `method`, `url`, `startedAt`, `requestHeaders`, `requestBodyBytes`, `requestContentType`.
  - `abstract interface class HttpTrafficCollector`:
    - `Future<HttpRequestContext?> startRequest(...)`
    - `Future<void> completeResponse(...)`
    - `void failRequest(...)`
  - `class DefaultHttpTrafficCollector implements HttpTrafficCollector`
  - `abstract interface class RealtimeTrafficCollector`:
    - `void recordConnection(...)`
    - `void recordFrame(...)`
    - `void recordClose(...)`
  - `class DefaultRealtimeTrafficCollector implements RealtimeTrafficCollector`
  - `abstract interface class HttpCaptureAdapter`:
    - `HttpTrafficCollector get collector;`
    - `InspectorSession get session;`
  - `abstract interface class RealtimeCaptureAdapter`:
    - `RealtimeTrafficCollector get collector;`
    - `InspectorSession get session;`

- [ ] **Step 1: Viết test cho `DefaultHttpTrafficCollector` và `DefaultRealtimeTrafficCollector`**
  Viết `packages/interceptly/test/adapter/traffic_collectors_test.dart` kiểm tra:
  - `startRequest` tạo `HttpRequestContext`, lưu pending record vào `InspectorSession`.
  - `completeResponse` tính đúng `durationMs`, áp dụng network simulation và ghi nhận `RawCapture`.
  - `failRequest` ghi nhận lỗi và thời gian thực thi.
  - Collector xử lý an toàn khi capture gặp lỗi (không ném exception ra ngoài).
  - `DefaultRealtimeTrafficCollector` ghi nhận connection, frame, và close vào session.

- [ ] **Step 2: Cài đặt `HttpRequestContext` và `NetworkCaptureAdapter` interfaces**
  Tạo `packages/interceptly/lib/src/adapter/http_request_context.dart` và `packages/interceptly/lib/src/adapter/network_capture_adapter.dart`.

- [ ] **Step 3: Cài đặt `HttpTrafficCollector` & `DefaultHttpTrafficCollector`**
  Tạo `packages/interceptly/lib/src/adapter/http_traffic_collector.dart` kế thừa logic từ `InspectorSession` và `guardCapture`.

- [ ] **Step 4: Cài đặt `RealtimeTrafficCollector` & `DefaultRealtimeTrafficCollector`**
  Tạo `packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart`.

- [ ] **Step 5: Export các SPI ra `packages/interceptly/lib/interceptly.dart`**
  Cập nhật file export chính của Core.

- [ ] **Step 6: Chạy test và phân tích tĩnh**
  Run: `flutter test packages/interceptly/test/adapter/traffic_collectors_test.dart`
  Run: `dart analyze packages/interceptly`
  Expected: PASS và 0 issues.

- [ ] **Step 7: Commit**
  ```bash
  git add packages/interceptly/lib/ packages/interceptly/test/
  git commit -m "feat(core): introduce traffic collector contracts and default implementations"
  ```

---

### Task 2: Tái cấu trúc `interceptly_dio` sử dụng `HttpTrafficCollector`

**Files:**
- Modify: `packages/interceptly_dio/lib/src/interceptly_dio_interceptor.dart`
- Test: `packages/interceptly_dio/test/interceptly_dio_interceptor_test.dart`
- Test: `packages/interceptly_dio/test/dio_robustness_test.dart`

**Interfaces:**
- Consumes: `HttpTrafficCollector`, `DefaultHttpTrafficCollector`, `HttpCaptureAdapter`, `HttpRequestContext`.
- Produces: `class InterceptlyDioInterceptor extends Interceptor implements HttpCaptureAdapter`.

- [ ] **Step 1: Cập nhật `InterceptlyDioInterceptor` để implement `HttpCaptureAdapter`**
  - Khai báo constructor nhận `[InspectorSession? session, HttpTrafficCollector? collector]`.
  - Giữ getter `collector` và `session`.
  - Trong `onRequest`: chuyển sang gọi `collector.startRequest(...)`. Xử lý `SimulatedNetworkException` qua collector.
  - Trong `onResponse`: chuyển sang gọi `collector.completeResponse(...)`.
  - Trong `onError`: chuyển sang gọi `collector.failRequest(...)`.

- [ ] **Step 2: Chạy bộ test của `interceptly_dio`**
  Run: `flutter test packages/interceptly_dio/test`
  Run: `dart analyze packages/interceptly_dio`
  Expected: 100% tests PASS, 0 issues.

- [ ] **Step 3: Commit**
  ```bash
  git add packages/interceptly_dio/
  git commit -m "refactor(dio): migrate InterceptlyDioInterceptor to HttpTrafficCollector"
  ```

---

### Task 3: Tái cấu trúc `interceptly_http` sử dụng `HttpTrafficCollector`

**Files:**
- Modify: `packages/interceptly_http/lib/src/interceptly_http_client.dart`
- Test: `packages/interceptly_http/test/http_client_test.dart`
- Test: `packages/interceptly_http/test/http_client_e2e_test.dart`

**Interfaces:**
- Consumes: `HttpTrafficCollector`, `DefaultHttpTrafficCollector`, `HttpCaptureAdapter`, `HttpRequestContext`.
- Produces: `class InterceptlyHttpClient extends http.BaseClient implements HttpCaptureAdapter`.

- [ ] **Step 1: Cập nhật `InterceptlyHttpClient` để implement `HttpCaptureAdapter`**
  - Constructor nhận `[InspectorSession? session, HttpTrafficCollector? collector]`.
  - Thay thế đoạn code thủ công `recordPending` và `session.record(RawCapture)` bằng các cuộc gọi tương ứng vào `collector.startRequest`, `collector.completeResponse`, `collector.failRequest`.

- [ ] **Step 2: Chạy bộ test của `interceptly_http`**
  Run: `flutter test packages/interceptly_http/test`
  Run: `dart analyze packages/interceptly_http`
  Expected: 100% tests PASS, 0 issues.

- [ ] **Step 3: Commit**
  ```bash
  git add packages/interceptly_http/
  git commit -m "refactor(http): migrate InterceptlyHttpClient to HttpTrafficCollector"
  ```

---

### Task 4: Tái cấu trúc `interceptly_chopper` sử dụng `HttpTrafficCollector`

**Files:**
- Modify: `packages/interceptly_chopper/lib/src/interceptly_chopper_interceptor.dart`
- Test: `packages/interceptly_chopper/test/chopper_interceptor_test.dart`
- Test: `packages/interceptly_chopper/test/chopper_robustness_test.dart`

**Interfaces:**
- Consumes: `HttpTrafficCollector`, `DefaultHttpTrafficCollector`, `HttpCaptureAdapter`, `HttpRequestContext`.
- Produces: `class InterceptlyChopperInterceptor implements Interceptor, HttpCaptureAdapter`.

- [ ] **Step 1: Cập nhật `InterceptlyChopperInterceptor` để implement `HttpCaptureAdapter`**
  - Constructor nhận `[InspectorSession? session, HttpTrafficCollector? collector]`.
  - Thay thế logic `session.recordPending` và `session.record(RawCapture)` bằng `collector.startRequest`, `collector.completeResponse`, `collector.failRequest`.

- [ ] **Step 2: Chạy bộ test của `interceptly_chopper`**
  Run: `flutter test packages/interceptly_chopper/test`
  Run: `dart analyze packages/interceptly_chopper`
  Expected: 100% tests PASS, 0 issues.

- [ ] **Step 3: Commit**
  ```bash
  git add packages/interceptly_chopper/
  git commit -m "refactor(chopper): migrate InterceptlyChopperInterceptor to HttpTrafficCollector"
  ```

---

### Task 5: Tái cấu trúc `interceptly_web_socket` sử dụng `RealtimeTrafficCollector`

**Files:**
- Modify: `packages/interceptly_web_socket/lib/src/interceptly_web_socket_channel.dart`
- Test: `packages/interceptly_web_socket/test/interceptly_web_socket_channel_test.dart`
- Test: `packages/interceptly_web_socket/test/stress/websocket_concurrency_stress_test.dart`

**Interfaces:**
- Consumes: `RealtimeTrafficCollector`, `DefaultRealtimeTrafficCollector`, `RealtimeCaptureAdapter`.
- Produces: `class InterceptlyWebSocketChannel extends StreamChannelMixin implements WebSocketChannel, RealtimeCaptureAdapter`.

- [ ] **Step 1: Cập nhật `InterceptlyWebSocketChannel` để implement `RealtimeCaptureAdapter`**
  - Constructor nhận `[RealtimeTrafficCollector? collector]`.
  - Thay thế các lệnh gọi trực tiếp `_client.recordRealtimeConnection`, `_client.recordRealtimeFrame`, `_client.closeRealtimeConnection` bằng `collector.recordConnection`, `collector.recordFrame`, `collector.recordClose`.

- [ ] **Step 2: Chạy bộ test của `interceptly_web_socket`**
  Run: `flutter test packages/interceptly_web_socket/test`
  Run: `dart analyze packages/interceptly_web_socket`
  Expected: 100% tests PASS, 0 issues.

- [ ] **Step 3: Commit**
  ```bash
  git add packages/interceptly_web_socket/
  git commit -m "refactor(web_socket): migrate InterceptlyWebSocketChannel to RealtimeTrafficCollector"
  ```

---

### Task 6: Nghiệm thu Monorepo & Cập nhật Tài liệu SPI

**Files:**
- Modify: `README.md`
- Modify: `packages/interceptly/README.md`

**Interfaces:**
- Produces: Toàn bộ monorepo sạch sẽ 100%, tài liệu hướng dẫn viết custom adapter thông qua SPI `HttpTrafficCollector` / `RealtimeTrafficCollector`.

- [ ] **Step 1: Cập nhật tài liệu Core SPI**
  Mô tả cách cộng đồng có thể tự viết adapter cho gRPC, GraphQL hoặc custom network client bằng cách sử dụng `HttpTrafficCollector` hoặc `RealtimeTrafficCollector`.

- [ ] **Step 2: Kiểm tra toàn diện Monorepo với Melos**
  Run: `dart pub global run melos run analyze` -> 0 issues.
  Run: `dart analyze packages/interceptly/example` -> 0 issues.
  Run: `dart pub global run melos run test` -> 100% tests PASS across all 5 packages.

- [ ] **Step 3: Commit**
  ```bash
  git add README.md packages/interceptly/README.md
  git commit -m "docs: document adapter SPI and traffic collector architecture"
  ```
