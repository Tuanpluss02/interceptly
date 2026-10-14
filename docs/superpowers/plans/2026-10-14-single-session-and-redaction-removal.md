# Strict Single Session & Complete Redaction Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chuyển đổi toàn bộ hệ thống sang mô hình duy nhất 1 Session (`InspectorSession.instance`), loại bỏ triệt để mọi cơ chế phân mảnh/fallback session, đồng thời xóa bỏ hoàn toàn 100% tính năng Redacted trên toàn bộ codebase mà không để lại code deprecated hay fallback thừa.

**Architecture:** 
1. **Strict Single Session:** Mọi adapter vệ tinh (`interceptly_dio`, `interceptly_http`, `interceptly_chopper`, `interceptly_web_socket`), controller (`Interceptly`), collector (`DefaultHttpTrafficCollector`, `DefaultRealtimeTrafficCollector`) và UI (`InterceptlyScreen`, FAB overlay) chỉ sử dụng duy nhất một phiên làm việc toàn cục `InspectorSession.instance`. Xóa bỏ mọi tham số `session` và `interceptly` khỏi constructor các adapter, factory methods và controller; xóa biến `_activeSession`.
2. **Complete Redaction Removal:** Loại bỏ `BodyRedactor`, `redactedHeaders`, `redactedQueryParams`, `redactOnExport` khỏi settings, capture pipeline, realtime collector, exporters (HAR, cURL, Postman) và UI sharing. Dữ liệu mạng được thu thập và xuất ra nguyên bản với hiệu năng tối đa (không tốn CPU clone/masking; `CapturePipeline.record()` chuyển trực tiếp `capture` mà không cấp phát lại đối tượng).
3. **Capture Guard Idiom:** Xóa bỏ `abstract final class CaptureGuard` và các top-level function `redactHeaders`, `sanitizeUrl`. Giữ `guardCapture`, `guardCaptureAsync`, `headerValue` là các top-level functions chuẩn theo Effective Dart.
4. **Async Lifecycle Testing:** Bổ sung `InspectorSession.resetForTesting()` dạng async (`Future<void>`) để await `dispose()`, reset `_defaultSettings` và reset `Interceptly.instance` nhằm chống rò rỉ isolate giữa các test suite.

**Tech Stack:** Dart 3.5+, Flutter 3.10+, Melos Monorepo, dio, http, chopper, web_socket_channel.

**Spec:** Quyết định kiến trúc ngày 2026-10-14: "chỉ duy nhất 1 session, không cần phân biệt gì cả, không fallback, không deprecated, xoá hoàn toàn Redacted."

## Global Constraints

- Không dùng `@deprecated` hay fallback logic: Xóa sạch các tham số/phương thức cũ (Clean breaking change).
- Phân tích tĩnh: 100% mã nguồn qua `dart analyze` (hoặc `melos run analyze`) đạt 0 warnings, 0 errors.
- Test suites: Toàn bộ test suite sau khi dọn dẹp và cập nhật phải PASS 100%.
- Thư mục làm việc: `/Users/tuanpluss02/Documents/Boltx/BDS/bds_thm/packages/interceptly`.

## Review Focus

- Không còn bất kỳ tham chiếu nào đến `_activeSession` hoặc tham số `session` trong các hàm public của `Interceptly`, `DefaultHttpTrafficCollector`, `DefaultRealtimeTrafficCollector` và các adapter.
- `CapturePipeline.record()` chuyển trực tiếp `RawCapture` vào queue/isolate mà không qua bước clone/masking (zero allocation overhead).
- Tất cả các exporter (`HarExporter`, `CurlGenerator`, `PostmanExporter`) chỉ nhận dữ liệu cần thiết, không còn cờ `redactOnExport` hay tham số redaction.
- `InterceptlyWebSocketChannel` cùng các factory `connect`, `wrap` khởi tạo tinh gọn chỉ với `(inner, {uri, sessionId, collector, headers})`.
- Reset singleton an toàn trong Unit Test (`await InspectorSession.resetForTesting()`) dọn sạch isolate, file temp và settings để các test suite không làm bẩn state của nhau.

---

### Task 1: Xóa bỏ hoàn toàn tính năng Redaction trong Core Models, Pipeline, Collectors & Tests

**Files:**
- Modify: `packages/interceptly/lib/src/model/interceptly_settings.dart`
- Modify: `packages/interceptly/lib/src/capture/capture_guard.dart`
- Modify: `packages/interceptly/lib/src/session/capture_pipeline.dart`
- Modify: `packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart`
- Modify: `packages/interceptly/lib/interceptly.dart`
- Modify: `packages/interceptly/test/session/realtime_redaction_test.dart`
- Modify: `packages/interceptly/test/stress/robustness_test.dart`
- Modify: `packages/interceptly/test/ui/detail/detail_page_lazy_tabs_test.dart`
- Modify: `packages/interceptly/test/e2e/e2e_features_test.dart`
- Modify: `packages/interceptly/test/stress/final_adversarial_verification_stress_test.dart`
- Delete: `packages/interceptly/test/session/security_defaults_test.dart`
- Delete: `packages/interceptly/test/stress/memory_index_redaction_stress_test.dart`

**Interfaces:**
- Produces:
  - `class InterceptlySettings`: không còn `redactedHeaders`, `redactedQueryParams`, `bodyRedactor`, `normalizedRedactedHeaders`, `normalizedRedactedQueryParams`.
  - `capture_guard.dart`: xóa hoàn toàn `abstract final class CaptureGuard` và các top-level function `redactHeaders`, `sanitizeUrl`. Giữ lại top-level functions `guardCapture`, `guardCaptureAsync`, `headerValue`.
  - `class CapturePipeline`: `record(RawCapture capture)` đẩy capture trực tiếp không khởi tạo lại `RawCapture`; xóa `redactInlineBytes`, `redactTransferable`.
  - `DefaultRealtimeTrafficCollector`: `recordFrame` lưu payload thô không mã hóa/clone, xóa `_redactText`.
  - `interceptly.dart`: không còn export `BodyRedactor`.

- [ ] **Step 1: Cập nhật `InterceptlySettings`**
  - Xóa `typedef BodyRedactor`.
  - Xóa `redactedHeaders`, `redactedQueryParams`, `bodyRedactor` trong constructor, fields, và `copyWith`.
  - Xóa `_normalizedCache`, `_normalizedQueryCache`, `normalizedRedactedHeaders`, `normalizedRedactedQueryParams`.

- [ ] **Step 2: Dọn dẹp `capture_guard.dart`**
  - Xóa class `CaptureGuard`.
  - Xóa 2 hàm top-level alias: `redactHeaders` và `sanitizeUrl`.
  - Giữ nguyên các top-level functions `guardCapture`, `guardCaptureAsync`, `headerValue`.

- [ ] **Step 3: Cập nhật `CapturePipeline` & `RealtimeTrafficCollector`**
  - Trong `CapturePipeline`: bỏ `_normalizedRedactedHeaders`, `_normalizedRedactedQueryParams`.
  - Sửa `CapturePipeline.record(RawCapture capture)`: đẩy trực tiếp `capture` vào queue hoặc isolate (`_sendCapture(capture)`), không khởi tạo lại `RawCapture(...)` trung gian.
  - Xóa 2 helper tĩnh: `redactInlineBytes` và `redactTransferable`.
  - Trong `RealtimeTrafficCollector.recordFrame`: bỏ gọi `bodyRedactor` và `_redactText`, gán thẳng `payload` vào `RealtimeFrame`. Xóa hàm `_redactText`.

- [ ] **Step 4: Dọn dẹp export trong `interceptly.dart` và test files liên quan**
  - Trong `interceptly.dart`: sửa `export 'src/model/interceptly_settings.dart' show InterceptlySettings;` (xóa `BodyRedactor`).
  - Xóa file test cũ: `security_defaults_test.dart` và `memory_index_redaction_stress_test.dart`.
  - Trong `realtime_redaction_test.dart`: xóa các test case kiểm tra redaction text/binary, chỉ giữ lại kiểm tra `shouldCapture` và frame payload nguyên bản.
  - Trong `test/stress/robustness_test.dart`: xóa nhóm test case `Security and Session settings` (hoặc chuyển test `shouldCapture` sang nhóm độc lập, xóa assertion liên quan đến `redactedHeaders`).
  - Trong `test/ui/detail/detail_page_lazy_tabs_test.dart`: xóa nhóm `R1 - Pre-Normalized Redacted Headers Caching`.
  - Trong `test/e2e/e2e_features_test.dart`: xóa test case `[F4] Redacted headers case-insensitively masks secrets` và test exporter redaction tương ứng.
  - Trong `test/stress/final_adversarial_verification_stress_test.dart`: xóa test case `Vector 6: Redacted headers pre-normalization`.

- [ ] **Step 5: Chạy test và phân tích tĩnh Task 1**
  Run: `flutter test packages/interceptly/test/session/`
  Run: `flutter test packages/interceptly/test/stress/robustness_test.dart`
  Run: `dart analyze packages/interceptly`
  Expected: PASS các test core; nếu còn lỗi analyze thì chỉ giới hạn ở các exporter chưa sửa ở Task 2.

- [ ] **Step 6: Commit**
  ```bash
  git add packages/interceptly/
  git commit -m "refactor(core): remove all redaction logic from settings, pipeline, collectors, and core tests"
  ```

---

### Task 2: Xóa bỏ Redaction khỏi Exporters (`HarExporter`, `CurlGenerator`, `PostmanExporter`, `ShareHandler`)

**Files:**
- Modify: `packages/interceptly/lib/src/export/har_exporter.dart`
- Modify: `packages/interceptly/lib/src/export/curl_generator.dart`
- Modify: `packages/interceptly/lib/src/export/postman_exporter.dart`
- Modify: `packages/interceptly/lib/src/ui/detail/share_handler.dart`
- Modify: `packages/interceptly/test/export/export_hardening_test.dart`
- Modify: `packages/interceptly/test/export/share_handler_test.dart`
- Modify: `packages/interceptly/test/export_roundtrip_test.dart`

**Interfaces:**
- Produces:
  - `HarExporter.toJson(records)` và `HarExporter.toMap(records)`: không còn `redactOnExport`, `redactedHeaders`, `redactedQueryParams`.
  - `CurlGenerator.fromRecord(record)`: không còn `redactOnExport`, `redactedHeaders`, `redactedQueryParams`.
  - `PostmanExporter.toJson(records, {collectionName})` và `toMap(records, {collectionName})`: không còn `redactOnExport`, `redactedHeaders`, `redactedQueryParams`.
  - `ShareHandler(context, fabKey)`: không còn `redactOnExport`.

- [ ] **Step 1: Cập nhật `HarExporter`**
  - Xóa `_defaultRedactedHeaders`, `_defaultRedactedQueryParams`.
  - Xóa tham số `redactOnExport`, `redactedHeaders`, `redactedQueryParams` khỏi `toJson`, `toMap`, `fromRecords`, `_entryFromRecord`.
  - Render trực tiếp request headers và query parameters nguyên bản.

- [ ] **Step 2: Cập nhật `CurlGenerator`**
  - Xóa `_defaultRedactedHeaders`, `_defaultRedactedQueryParams`.
  - Xóa tham số `redactOnExport`, `redactedHeaders`, `redactedQueryParams` khỏi `fromRecord`.
  - Xuất toàn bộ headers và URL nguyên bản.

- [ ] **Step 3: Cập nhật `PostmanExporter` & `ShareHandler`**
  - Xóa các hằng số và tham số redaction khỏi `PostmanExporter.toJson` và `toMap`.
  - Trong `ShareHandler`: xóa cờ `redactOnExport` trong constructor chính và factory `withShare`.

- [ ] **Step 4: Cập nhật các test suite exporter**
  - Sửa `export_hardening_test.dart`, `share_handler_test.dart`, `export_roundtrip_test.dart` để bỏ các tham số `redactOnExport`, `redactedHeaders`.
  - Xác nhận exporter xuất ra thông tin request/URL đầy đủ không bị thay thế bằng `[REDACTED]`.

- [ ] **Step 5: Chạy test và phân tích tĩnh Task 2**
  Run: `flutter test packages/interceptly/test/export/`
  Run: `flutter test packages/interceptly/test/export_roundtrip_test.dart`
  Run: `dart analyze packages/interceptly`
  Expected: PASS và 0 warnings/errors trong toàn bộ `packages/interceptly`.

- [ ] **Step 6: Commit**
  ```bash
  git add packages/interceptly/
  git commit -m "refactor(export): remove redaction options from HAR, cURL, and Postman exporters"
  ```

---

### Task 3: Chuẩn hóa Strict Single Session trong Core Engine, Collectors & UI

**Files:**
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart`
- Modify: `packages/interceptly/lib/src/core/interceptly_controller.dart`
- Modify: `packages/interceptly/lib/src/adapter/http_traffic_collector.dart`
- Modify: `packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart`
- Modify: `packages/interceptly/lib/src/adapter/network_capture_adapter.dart`
- Modify: `packages/interceptly/lib/src/ui/screens/interceptly_screen.dart`
- Modify: `packages/interceptly/test/adapter/traffic_collectors_test.dart`
- Modify: `packages/interceptly/test/ui/widgets/theme_isolation_test.dart`
- Modify: `packages/interceptly/test/interceptly_test.dart`

**Interfaces:**
- Produces:
  - `InspectorSession.instance`: session duy nhất toàn cục. Thêm `@visibleForTesting static Future<void> resetForTesting() async`.
  - `Interceptly`:
    - Constructor: `Interceptly({InterceptlySettings? settings})`: luôn trỏ vào `InspectorSession.instance` và áp dụng `settings` nếu có.
    - `static Future<void> init(...)`: xóa bỏ hoàn toàn tham số `InspectorSession? session`.
    - Xóa bỏ biến `_activeSession`.
    - `static void resetForTesting()`: reset `_sharedInstance = null`.
  - `DefaultHttpTrafficCollector()`: constructor không nhận tham số. `InspectorSession get session => InspectorSession.instance;`.
  - `DefaultRealtimeTrafficCollector()`: constructor không nhận tham số. `InspectorSession get session => InspectorSession.instance;`.
  - `InterceptlyScreen({super.key, InspectorSessionView? session})`: mặc định `session = session ?? InspectorSession.instance`.

- [ ] **Step 1: Cập nhật `InspectorSession.resetForTesting()`**
  - Thêm phương thức reset bất đồng bộ an toàn:
    ```dart
    @visibleForTesting
    static Future<void> resetForTesting() async {
      await _instance?.dispose();
      _instance = null;
      _defaultSettings = const InterceptlySettings();
      Interceptly.resetForTesting();
    }
    ```

- [ ] **Step 2: Tái cấu trúc `Interceptly` facade trong `interceptly_controller.dart`**
  - Xóa biến file-level `InspectorSession? _activeSession;`.
  - Sửa `Interceptly.init`: xóa tham số `InspectorSession? session`. Nếu truyền `settings`, gọi `InspectorSession.instance.configureSession(settings)`. Cập nhật docstring loại bỏ tham chiếu `redactedHeaders`.
  - Sửa constructor `Interceptly({InterceptlySettings? settings})`: xóa tham số `session`, gán `_session = InspectorSession.instance`. Nếu `settings != null`, áp dụng `_session.configureSession(settings)`.
  - Thêm `@visibleForTesting static void resetForTesting() => _sharedInstance = null;`.
  - Sửa `showInspector` và `_openInspector`: luôn truyền `session: InspectorSession.instance`.

- [ ] **Step 3: Chuẩn hóa `DefaultHttpTrafficCollector` & `DefaultRealtimeTrafficCollector`**
  - Sửa `DefaultHttpTrafficCollector`: constructor rỗng `DefaultHttpTrafficCollector()`, xóa bỏ biến `_session`, getter: `InspectorSession get session => InspectorSession.instance;`.
  - Sửa `DefaultRealtimeTrafficCollector`: constructor rỗng `DefaultRealtimeTrafficCollector()`, xóa bỏ biến `_session`, getter: `InspectorSession get session => InspectorSession.instance;`.
  - Giữ contract trong `HttpCaptureAdapter` và `RealtimeCaptureAdapter`: `InspectorSession get session;`.

- [ ] **Step 4: Cập nhật `InterceptlyScreen`**
  - Sửa constructor `InterceptlyScreen`:
    ```dart
    const InterceptlyScreen({super.key, InspectorSessionView? session})
        : session = session ?? InspectorSession.instance;
    ```
  - Giúp `InterceptlyScreen` tự động gắn vào session duy nhất của app mà không cần truyền thủ công, đồng thời giữ tương thích cho widget test nếu cần mock view.

- [ ] **Step 5: Cập nhật Core Unit & Widget Tests**
  - Sửa `packages/interceptly/test/adapter/traffic_collectors_test.dart`: trong `setUp` và `tearDown` gọi `await InspectorSession.resetForTesting()`. Collector khởi tạo dạng `DefaultHttpTrafficCollector()` và kiểm tra dữ liệu qua `InspectorSession.instance`.
  - Cập nhật `test/interceptly_test.dart` và `test/ui/widgets/theme_isolation_test.dart` phù hợp với chữ ký mới.

- [ ] **Step 6: Chạy test và phân tích tĩnh Task 3**
  Run: `flutter test packages/interceptly/test/adapter/traffic_collectors_test.dart`
  Run: `flutter test packages/interceptly/test/ui/widgets/theme_isolation_test.dart`
  Run: `dart analyze packages/interceptly`
  Expected: PASS và 0 warnings/errors trong `packages/interceptly`.

- [ ] **Step 7: Commit**
  ```bash
  git add packages/interceptly/
  git commit -m "refactor(core): enforce strict single session across controller, collectors, and UI"
  ```

---

### Task 4: Tinh gọn toàn bộ Satellite Adapters (Dio, Http, Chopper, WebSocket)

**Files:**
- Modify: `packages/interceptly_dio/lib/src/interceptly_dio_interceptor.dart`
- Modify: `packages/interceptly_dio/test/interceptly_dio_interceptor_test.dart`
- Modify: `packages/interceptly_dio/test/dio_onerror_test.dart`
- Modify: `packages/interceptly_http/lib/src/interceptly_http_client.dart`
- Modify: `packages/interceptly_http/test/http_client_test.dart`
- Modify: `packages/interceptly_http/test/http_client_e2e_test.dart`
- Modify: `packages/interceptly_chopper/lib/src/interceptly_chopper_interceptor.dart`
- Modify: `packages/interceptly_chopper/test/chopper_interceptor_test.dart`
- Modify: `packages/interceptly_chopper/test/chopper_interceptor_adversarial_test.dart`
- Modify: `packages/interceptly_web_socket/lib/src/interceptly_web_socket_channel.dart`
- Modify: `packages/interceptly_web_socket/test/interceptly_web_socket_channel_test.dart`
- Modify: `packages/interceptly_web_socket/test/stress/websocket_concurrency_stress_test.dart`

**Interfaces:**
- Produces:
  - `InterceptlyDioInterceptor([HttpTrafficCollector? collector])`: không nhận `session`.
  - `InterceptlyHttpClient(http.Client inner, [HttpTrafficCollector? collector])`: không nhận `session`.
  - `InterceptlyHttpClient.wrap(http.Client inner, [HttpTrafficCollector? collector])`: không nhận `session`.
  - `InterceptlyChopperInterceptor([HttpTrafficCollector? collector])`: không nhận `session`.
  - `InterceptlyWebSocketChannel(inner, {uri, sessionId, collector, headers})`: không nhận `interceptly`, không nhận `session`.
  - `InterceptlyWebSocketChannel.connect(url, {protocols, sessionId, collector, headers})`: không nhận `interceptly`, không nhận `session`.
  - `InterceptlyWebSocketChannel.wrap(inner, {uri, sessionId, collector, headers})`: không nhận `interceptly`, không nhận `session`.
  - Tất cả các adapter có `InspectorSession get session => InspectorSession.instance;`.

- [ ] **Step 1: Cập nhật `InterceptlyDioInterceptor` và các test**
  - Sửa constructor: `InterceptlyDioInterceptor([HttpTrafficCollector? collector]) : collector = collector ?? DefaultHttpTrafficCollector();`.
  - Getter: `InspectorSession get session => InspectorSession.instance;`.
  - Cập nhật `interceptly_dio_interceptor_test.dart` và `dio_onerror_test.dart`: gọi `await InspectorSession.resetForTesting()` trong `setUp`/`tearDown`, loại bỏ truyền `session` vào `InterceptlyDioInterceptor()`.

- [ ] **Step 2: Cập nhật `InterceptlyHttpClient` và các test**
  - Sửa constructor và factory `wrap`: chỉ nhận `(http.Client inner, [HttpTrafficCollector? collector])`.
  - Getter: `InspectorSession get session => InspectorSession.instance;`.
  - Cập nhật `http_client_test.dart` và `http_client_e2e_test.dart`: xóa bỏ truyền `session` vào client, dùng `InspectorSession.resetForTesting()`.

- [ ] **Step 3: Cập nhật `InterceptlyChopperInterceptor` và các test**
  - Sửa constructor: `InterceptlyChopperInterceptor([HttpTrafficCollector? collector])`.
  - Getter: `InspectorSession get session => InspectorSession.instance;`.
  - Cập nhật `chopper_interceptor_test.dart` và `chopper_interceptor_adversarial_test.dart`: xóa bỏ truyền `session` vào interceptor.

- [ ] **Step 4: Cập nhật `InterceptlyWebSocketChannel` và các test**
  - Xóa bỏ hoàn toàn tham số `Interceptly? interceptly` và `InspectorSession? session` khỏi constructor chính, factory `connect`, và factory `wrap`.
  - Xóa bỏ biến `_interceptly` và `_resolvedInterceptly`. Getter `Interceptly get interceptly => Interceptly.instance;`.
  - Xóa bỏ logic fallback nhiều tầng; `collector` mặc định khởi tạo `DefaultRealtimeTrafficCollector()`.
  - Getter: `InspectorSession get session => InspectorSession.instance;`.
  - Cập nhật `interceptly_web_socket_channel_test.dart` và `websocket_concurrency_stress_test.dart`: xóa các test thử nghiệm custom session, thay bằng `InspectorSession.resetForTesting()`.

- [ ] **Step 5: Chạy test toàn bộ các adapter**
  Run: `flutter test packages/interceptly_dio/test`
  Run: `flutter test packages/interceptly_http/test`
  Run: `flutter test packages/interceptly_chopper/test`
  Run: `flutter test packages/interceptly_web_socket/test`
  Expected: 100% test suites PASS.

- [ ] **Step 6: Commit**
  ```bash
  git add packages/interceptly_dio/ packages/interceptly_http/ packages/interceptly_chopper/ packages/interceptly_web_socket/
  git commit -m "refactor(adapters): remove redundant session/interceptly parameters across all adapters"
  ```

---

### Task 5: Cập nhật Example, Tài liệu và Xác thực Toàn diện (Melos)

**Files:**
- Modify: `packages/interceptly/example/lib/main.dart`
- Modify: `packages/interceptly/example/lib/src/example_truncation_presets.dart`
- Modify: `packages/interceptly/example/lib/src/example_home_page.dart`
- Modify: `packages/interceptly/example/lib/src/example_local_server.dart`
- Modify: `packages/interceptly/README.md`
- Modify: `packages/interceptly_dio/README.md`
- Modify: `packages/interceptly_http/README.md`
- Modify: `packages/interceptly_chopper/README.md`
- Modify: `packages/interceptly_web_socket/README.md`
- Modify: `README.md`

- [ ] **Step 1: Dọn dẹp Example App**
  - Trong `example/lib/main.dart` và `example/lib/src/example_truncation_presets.dart`: xóa `redactedHeaders`.
  - Trong `example/lib/src/example_home_page.dart` và `example_local_server.dart`: xóa phần demo mock request Redacted Headers/Tokens.

- [ ] **Step 2: Cập nhật tài liệu README**
  - Cập nhật README của tất cả các package: bỏ các hướng dẫn/tùy chọn về `redactedHeaders`, `redactedQueryParams`, `bodyRedactor`, và tham số `session` trong adapter.

- [ ] **Step 3: Chạy toàn bộ phân tích tĩnh và test trên toàn monorepo**
  Run: `melos run analyze`
  Run: `melos run test`
  Expected: 0 warnings, 0 errors, 100% test suites PASS trên cả 5 packages.

- [ ] **Step 4: Commit**
  ```bash
  git add .
  git commit -m "docs(all): update readme, example, and documentation for single-session and redaction-free architecture"
  ```
