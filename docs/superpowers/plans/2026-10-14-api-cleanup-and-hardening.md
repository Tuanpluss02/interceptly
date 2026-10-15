# API Cleanups, Isolate Supervision and Core Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Giải quyết triệt để toàn diện các rủi ro Isolate, Memory leak, Data Loss, Adapter latency và đồng bộ hóa các dọn dẹp API (loại bỏ alias thừa, thu hẹp SPI adapter, chuẩn hóa HAR Base64 và Set-Cookie).

**Architecture:** Tách biệt hoàn toàn luồng nghiệp vụ mạng (Critical Path) của ứng dụng khỏi luồng thu thập (Capture Pipeline). Áp dụng Dual-Budget Backpressure (count + bytes) và Isolate Watchdog tự phục hồi (Self-Healing). Đảm bảo Data Integrity tuyệt đối: fallback trung thực, per-side truncation chuẩn xác và cảnh báo data loss trên Replay/Export. Tối ưu UI & Search với pre-parsed domain và reactive search updates. Thực hiện breaking change sạch sẽ đối với các alias/constructor thừa.

**Tech Stack:** Dart >=3.5 <4.0, Flutter >=3.24, Melos 6, flutter_test.

**Spec:** Cuộc trao đổi review thiết kế adapter, rủi ro isolate/memory và hardening ngày 2026-10-14.

## Global Constraints

- Không dùng `@Deprecated` hay fallback layer cho các alias bị loại bỏ; xóa dứt điểm và cập nhật caller.
- Dual backpressure trên Main Isolate phải có trần cứng cả về số lượng (`maxQueuedEvents`) và dung lượng byte (`32MB`).
- Isolate crash hoặc init failure không được làm treo hệ thống hoặc nuốt im lặng capture; phải tự phục hồi hoặc fallback sang memory-only mode.
- Ràng buộc phiên bản đồng nhất toàn monorepo: `sdk: '>=3.5.0 <4.0.0'` và `flutter: '>=3.24.0'`.
- Sau mỗi task: `melos run analyze` phải đạt 0 warning / 0 error và toàn bộ test liên quan phải PASS.
- Mọi docstring tuân thủ chuẩn `///`. Commit theo chuẩn Conventional Commits (`feat:`, `fix:`, `refactor:`, `chore:`).

## Review Focus

1. **Isolate Crash Resilience:** Isolate bị kill hoặc ném uncaught exception giữa chừng không được làm kẹt `_inFlight` hay drop im lặng các capture tiếp theo.
2. **Honest Fallback Data Loss:** Khi ghi đĩa/serialize thất bại, `_fallbackEntry` phải bảo toàn kích thước gốc và đánh dấu `hasDataLoss = true`, không được trả về `complete(0)`.
3. **Per-Side Truncation Isolation:** Request không body (GET 0 byte) không bao giờ bị hiển thị cờ mất dữ liệu chỉ vì response cùng cặp bị cắt ngắn ở storage.
4. **Dio Latency Decoupling:** Ứng dụng nhận response ngay lập tức; không bị block bởi `compute` isolate hay tác vụ serialize JSON của Interceptly.
5. **WebSocket Row Integrity:** Mọi kết nối WebSocket (kể cả khi không truyền `uri`) đều phải sinh ra row hợp lệ trên UI và không gây rò rỉ bộ nhớ vô hạn trong `RealtimeStore`.

---

### Task 1: Đồng bộ phiên bản Flutter `>=3.24.0` & Assertion Bounds trong toàn bộ Monorepo

**Files:**
- Modify: `pubspec.yaml`
- Modify: `packages/interceptly/pubspec.yaml`
- Modify: `packages/interceptly_dio/pubspec.yaml`
- Modify: `packages/interceptly_http/pubspec.yaml`
- Modify: `packages/interceptly_chopper/pubspec.yaml`
- Modify: `packages/interceptly_web_socket/pubspec.yaml`
- Modify: `packages/interceptly/lib/src/model/interceptly_settings.dart`
- Modify: `packages/interceptly/test/session/clear_generation_test.dart`
- Modify: `packages/interceptly/test/stress/memory_index_boundary_stress_test.dart`
- Test: `packages/interceptly/test/model/interceptly_settings_test.dart`

**Interfaces:**
- Nâng `flutter: ">=3.10.0"` thành `flutter: ">=3.24.0"` trên cả 6 file `pubspec.yaml`.
- `InterceptlySettings` constructor asserts:
  - `assert(maxEntries > 0)`
  - `assert(maxQueuedEvents > 0)`
  - `assert(maxFramesPerSession > 0)`
  - `assert(previewTruncationBytes >= 0)`
  - `assert(bodyOffloadThreshold >= 0)`
  - `assert(maxUiPreviewBytes >= 0)`

- [ ] **Step 1: Viết test cho assertion boundaries của `InterceptlySettings`**
Trong `packages/interceptly/test/model/interceptly_settings_test.dart`:
```dart
test('asserts on non-positive capacities', () {
  expect(() => InterceptlySettings(maxEntries: 0), throwsAssertionError);
  expect(() => InterceptlySettings(maxQueuedEvents: 0), throwsAssertionError);
  expect(() => InterceptlySettings(maxFramesPerSession: 0), throwsAssertionError);
  expect(() => InterceptlySettings(bodyOffloadThreshold: -1), throwsAssertionError);
});
```

- [ ] **Step 2: Cập nhật 6 file `pubspec.yaml` và `InterceptlySettings`**
Nâng Flutter constraint lên `>=3.24.0` và thêm các `assert(...)` vào constructor `InterceptlySettings`.

- [ ] **Step 3: Cập nhật các test cũ truyền `maxEntries: 0`**
Trong `clear_generation_test.dart` và `memory_index_boundary_stress_test.dart`, chuyển sang kiểm tra `MemoryIndex(maxEntries: 0)` trực tiếp thay vì thông qua `InterceptlySettings`.

- [ ] **Step 4: Chạy test và verify**
Run: `cd packages/interceptly && flutter test test/model/interceptly_settings_test.dart test/session/clear_generation_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add pubspec.yaml packages/*/pubspec.yaml packages/interceptly/lib/ packages/interceptly/test/
git commit -m "chore: align Flutter SDK to >=3.24.0 and enforce assert boundaries in settings"
```

---

### Task 2: Sửa Bug Truncation trong `BodyDecodeService` và Quote cURL method

**Files:**
- Modify: `packages/interceptly/lib/src/session/body_decode_service.dart:120-125`
- Modify: `packages/interceptly/lib/src/export/curl_generator.dart:43`
- Test: `packages/interceptly/test/session/truncation_loss_test.dart`
- Test: `packages/interceptly/test/export/curl_generator_test.dart`

**Interfaces:**
- `BodyDecodeService.truncate(Uint8List? bytes, int maxBody, int previewLen) -> Uint8List?`: khi `maxBody <= 0`, trả về `bytes` nguyên vẹn (unlimited).
- `CurlGenerator.fromRecord(RequestRecord record)`: format `-X '$sanitizedMethod'`.

- [ ] **Step 1: Viết test failing cho `truncate` unlimited và cURL quote**
Trong `packages/interceptly/test/session/truncation_loss_test.dart`:
```dart
test('truncate returns entire byte array unmodified when maxBody <= 0 (unlimited)', () {
  final payload = Uint8List.fromList(List.generate(100, (i) => i));
  expect(BodyDecodeService.truncate(payload, 0, 10), equals(payload));
  expect(BodyDecodeService.truncate(payload, -1, 10), equals(payload));
});
```
Trong `curl_generator_test.dart`: assert `-X 'GET'`, `-X 'POST'`.

- [ ] **Step 2: Sửa `BodyDecodeService.truncate` và `CurlGenerator`**
```dart
static Uint8List? truncate(Uint8List? bytes, int maxBody, int previewLen) {
  if (bytes == null || bytes.isEmpty) return null;
  if (maxBody <= 0 || bytes.length <= maxBody) return bytes;
  final end = previewLen < bytes.length ? previewLen : bytes.length;
  return bytes.sublist(0, end);
}
```
Và `buffer.write(" -X '$sanitizedMethod'");`.

- [ ] **Step 3: Chạy test và commit**
Run: `cd packages/interceptly && flutter test test/session/truncation_loss_test.dart test/export/curl_generator_test.dart`
Expected: PASS
```bash
git add packages/interceptly/lib/src/session/body_decode_service.dart packages/interceptly/lib/src/export/curl_generator.dart packages/interceptly/test/
git commit -m "fix(core): preserve unlimited bodies in BodyDecodeService and quote cURL method"
```

---

### Task 3: Chuẩn hóa Header `Set-Cookie` (RFC 6265) và HAR Export Binary Base64

**Files:**
- Modify: `packages/interceptly/lib/src/capture/body_bytes.dart:42-50`
- Modify: `packages/interceptly/lib/src/export/har_exporter.dart:21,75-83,103-112`
- Test: `packages/interceptly/test/capture/body_bytes_test.dart`
- Test: `packages/interceptly/test/export/har_exporter_test.dart`

**Interfaces:**
- `normalizeHeaders(Map<String, Object?> headers) -> Map<String, String>`: `Set-Cookie` nối bằng `\n`; các header khác nối bằng `, `.
- `HarExporter`: creator version `'2.0.0'`; binary payload encode `base64` và kèm trường `'encoding': 'base64'`.

- [ ] **Step 1: Viết test failing cho `normalizeHeaders` và HAR binary base64**
```dart
test('normalizeHeaders joins set-cookie with newline instead of comma', () {
  final headers = {
    'set-cookie': [
      'session=abc; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/',
      'token=xyz; Path=/',
    ],
    'accept': ['text/html', 'application/xhtml+xml'],
  };
  final normalized = normalizeHeaders(headers);
  expect(normalized['set-cookie'], 'session=abc; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/\ntoken=xyz; Path=/');
  expect(normalized['accept'], 'text/html, application/xhtml+xml');
});
```

- [ ] **Step 2: Cập nhật `normalizeHeaders` và `HarExporter`**
Trong `normalizeHeaders`: check `key.toLowerCase() == 'set-cookie' ? '\n' : ', '`.
Trong `HarExporter`: nếu body là binary (hoặc `BodyDecodeService.isBinary`), set `content['encoding'] = 'base64'` và `content['text'] = base64Encode(bytes)`.

- [ ] **Step 3: Chạy test và commit**
Run: `cd packages/interceptly && flutter test test/capture/body_bytes_test.dart test/export/har_exporter_test.dart`
Expected: PASS
```bash
git add packages/interceptly/lib/src/capture/body_bytes.dart packages/interceptly/lib/src/export/har_exporter.dart packages/interceptly/test/
git commit -m "feat(export): preserve Set-Cookie headers with newline and export HAR binary as base64"
```

---

### Task 4: Thêm `IndexEntry.copyWith`, Domain Pre-parsing và Refactor `PendingTracker`

**Files:**
- Modify: `packages/interceptly/lib/src/model/index_entry.dart`
- Modify: `packages/interceptly/lib/src/model/request_filter.dart`
- Modify: `packages/interceptly/lib/src/session/pending_tracker.dart`
- Test: `packages/interceptly/test/model/index_entry_test.dart`
- Test: `packages/interceptly/test/pending_timeout_fake_async_test.dart`

**Interfaces:**
- `IndexEntry`: thêm trường `final String domain;` (parse 1 lần từ URL khi tạo `IndexEntry` qua `RequestFilter.extractDomain(url)`).
- `IndexEntry.copyWith(...) -> IndexEntry`.
- `RequestFilter.matches(RequestSummary entry)`: so khớp trực tiếp trên `(entry as? IndexEntry)?.domain ?? extractDomain(entry.url)`, loại bỏ hoàn toàn việc gọi `Uri.parse(url)` liên tục trong getter `entries`.

- [ ] **Step 1: Viết test cho `IndexEntry.copyWith` và pre-parsed `domain`**
- [ ] **Step 2: Thêm `domain` và `copyWith` vào `IndexEntry`**
- [ ] **Step 3: Refactor `PendingTracker` dùng `copyWith`**
Thay thế 2 khối sao chép 22 trường thủ công trong `closeRealtimeConnection` và `_onTimeout` bằng `current.copyWith(...)`.
- [ ] **Step 4: Cập nhật `RequestFilter.matches` tận dụng `entry.domain`**
- [ ] **Step 5: Chạy test và commit**
Run: `cd packages/interceptly && flutter test test/pending_timeout_fake_async_test.dart test/session/realtime_session_test.dart`
Expected: PASS
```bash
git add packages/interceptly/lib/src/model/index_entry.dart packages/interceptly/lib/src/model/request_filter.dart packages/interceptly/lib/src/session/pending_tracker.dart packages/interceptly/test/
git commit -m "refactor(core): pre-parse domain on IndexEntry, add copyWith and streamline pending tracking"
```

---

### Task 5: Isolate Supervision, Dual Backpressure (`inFlightBytes`), Lifecycle Guards & Circuit Breaker

**Files:**
- Modify: `packages/interceptly/lib/src/session/capture_pipeline.dart`
- Modify: `packages/interceptly/lib/src/session/writer_isolate.dart`
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart`
- Test: `packages/interceptly/test/session/isolate_resilience_test.dart`
- Test: `packages/interceptly/test/session/backpressure_bytes_test.dart`

**Interfaces:**
- `CapturePipeline`:
  - Thêm `int _inFlightBytes = 0;` (ngưỡng tối đa `maxInFlightBytes = 32 * 1024 * 1024`).
  - `_sendCapture` kiểm tra cả `_inFlight >= maxQueuedEvents` HOẶC `_inFlightBytes >= maxInFlightBytes`.
  - Thêm cờ `_isDisposed`. Trong `_performInit`, kiểm tra `if (_isDisposed)` sau mỗi `await`.
  - Circuit Breaker: nếu `_performInit` gặp exception, đánh dấu `_initFailed = true` và chuyển sang chế độ degraded (in-memory fallback), không để `_initFuture = null` nhằm triệt tiêu retry storm.
  - Watchdog: `WriterIsolate` emit sự kiện qua stream khi error/exit. `CapturePipeline` reset `_inFlight = 0, _inFlightBytes = 0`, thử respawn tối đa 3 lần; nếu vượt quá thì fallback sang in-memory mode an toàn.
- `InspectorSession`:
  - `enable()`: thêm `if (_isDisposed || _enabled) return;`.

- [ ] **Step 1: Viết test failing cho Isolate Crash & Backpressure Bytes**
Trong `test/session/isolate_resilience_test.dart`:
```dart
test('isolate death resets inFlight and allows subsequent captures via fallback or respawn', () async {
  // Spawn session, kill isolate forcibly via WriterIsolate.rawIsolate.kill
  // Record subsequent captures
  // Verify captures are not dropped silently due to stuck inFlight
});
test('dual backpressure drops capture when inFlightBytes exceeds 32MB', () async {
  // Send large raw captures, verify droppedCount increases when bytes saturated
});
test('enable after dispose does not revive session', () {
  final session = InspectorSession();
  session.dispose();
  session.enable();
  expect(session.isEnabled, isFalse);
});
```

- [ ] **Step 2: Triển khai Dual Backpressure và Watchdog trong `CapturePipeline` & `WriterIsolate`**
Thêm `_inFlightBytes`, `_isDisposed`, error callback từ `_errorPort/_exitPort` và guard `_isDisposed` trong `_performInit` và `enable()`.

- [ ] **Step 3: Chạy test xác nhận pass**
Run: `cd packages/interceptly && flutter test test/session/isolate_resilience_test.dart test/session/backpressure_bytes_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**
```bash
git add packages/interceptly/lib/src/session/ packages/interceptly/test/
git commit -m "fix(core): implement isolate supervisor watchdog, dual byte backpressure, and lifecycle guards"
```

---

### Task 6: Honest Fallback & Loại bỏ Single-Flag Packed Format Hack

**Files:**
- Modify: `packages/interceptly/lib/src/session/writer_isolate.dart`
- Modify: `packages/interceptly/lib/src/session/detail_loader.dart:70-75`
- Modify: `packages/interceptly/lib/src/session/body_decode_service.dart:150-175`
- Test: `packages/interceptly/test/session/honest_fallback_test.dart`
- Test: `packages/interceptly/test/session/per_side_truncation_test.dart`

**Interfaces:**
- `_fallbackEntry(RawCapture capture)`: giữ nguyên `requestSizeBytes` và `responseSizeBytes`; đặt truncation thành `stage: TruncationStage.storage` và `hasDataLoss = true`.
- `_packBodies`: loại bỏ byte cờ gộp `out[offset] = (reqTruncated || resTruncated) ? 1 : 0`, xoá `typedef _PackedBodies`.
- `DetailLoader`: loại bỏ hoàn toàn việc gọi `markStorageCut` từ kết quả unpack; tin cậy hoàn toàn vào `entry.requestTruncation` và `entry.responseTruncation` đã có sẵn.

- [ ] **Step 1: Viết test failing cho Honest Fallback và Per-Side Truncation Isolation**
```dart
test('fallback entry preserves original size and reports storage truncation with hasDataLoss=true', () {
  final capture = RawCapture(id: '1', method: 'POST', url: 'https://api.com', requestSizeBytes: 500);
  final entry = fallbackEntryForTesting(capture);
  expect(entry.requestSizeBytes, equals(500));
  expect(entry.requestTruncation.hasDataLoss, isTrue);
});

test('detail loader does not mark request as storage cut when only response was truncated', () async {
  // Load entry with 0 byte request and truncated response
  // Assert record.requestTruncation.hasDataLoss is false
  // Assert record.responseTruncation.hasDataLoss is true
});
```

- [ ] **Step 2: Triển khai Honest Fallback và dọn dẹp `DetailLoader` & Packed Format**
Cập nhật `_fallbackEntry`, loại bỏ cờ gộp ở đuôi pack, xoá khối ghi đè `markStorageCut` trong `DetailLoader`.

- [ ] **Step 3: Chạy test và commit**
Run: `cd packages/interceptly && flutter test test/session/honest_fallback_test.dart test/session/per_side_truncation_test.dart`
Expected: PASS
```bash
git add packages/interceptly/lib/src/session/ packages/interceptly/test/
git commit -m "fix(core): ensure honest fallback reporting and clean per-side storage truncation"
```

---

### Task 7: Data Loss Awareness trong Replay, cURL & HAR Exporter

**Files:**
- Modify: `packages/interceptly/lib/src/ui/detail/replay_handler.dart:220-235`
- Modify: `packages/interceptly/lib/src/export/curl_generator.dart:50-65`
- Modify: `packages/interceptly/lib/src/export/har_exporter.dart:75-85`
- Test: `packages/interceptly/test/export/curl_generator_test.dart`
- Test: `packages/interceptly/test/export/har_exporter_test.dart`
- Test: `packages/interceptly/test/ui/replay_handler_test.dart`

**Interfaces:**
- `ReplayHandler._sendRequest`: nếu `truncation.hasDataLoss == true`, hiển thị toast/confirmation dialog cảnh báo body đã bị cắt ngắn trước khi replay.
- `CurlGenerator.fromRecord`: nếu `record.requestTruncation.hasDataLoss == true`, chèn comment cảnh báo `# WARNING: Request body was truncated during capture (${retained}/${original} bytes)\n`.
- `HarExporter`: nếu `responseTruncation.hasDataLoss == true`, chèn `comment: 'Payload truncated from original ${record.responseSizeBytes} bytes'` trong `content`.

- [ ] **Step 1: Viết test failing cho Data Loss warnings trong Replay, cURL và HAR**
- [ ] **Step 2: Cập nhật `ReplayHandler`, `CurlGenerator` và `HarExporter`**
- [ ] **Step 3: Chạy test và commit**
Run: `cd packages/interceptly && flutter test test/export/curl_generator_test.dart test/export/har_exporter_test.dart`
Expected: PASS
```bash
git add packages/interceptly/lib/src/ui/detail/replay_handler.dart packages/interceptly/lib/src/export/ packages/interceptly/test/
git commit -m "feat(export): guard replay and export with clear data loss warnings"
```

---

### Task 8: Decoupling Dio Adapter khỏi Critical Path & Loại bỏ `compute`

**Files:**
- Modify: `packages/interceptly_dio/lib/src/interceptly_dio_interceptor.dart`
- Test: `packages/interceptly_dio/test/interceptly_dio_interceptor_test.dart`
- Test: `packages/interceptly_dio/test/dio_latency_test.dart`

**Interfaces:**
- `onRequest`: chỉ await network simulation nếu có cấu hình simulation; không block `handler.next(options)`.
- `onResponse`: loại bỏ `compute(_encodeJsonBytes)`. Gọi `handler.next(response)` ngay khi nhận response (sau simulation delay nếu có). Tác vụ serialize body JSON và ghi capture chạy bất đồng bộ qua `unawaited(guardCaptureAsync(...))`.
- Sử dụng hàm encode JSON trực tiếp an toàn với `jsonEncode` trong try-catch, không spawn isolate mới trên mỗi response.

- [ ] **Step 1: Viết test đảm bảo `handler.next` được gọi nhanh chóng không chờ serialize**
- [ ] **Step 2: Triển khai fire-and-forget capture trong `InterceptlyDioInterceptor`**
- [ ] **Step 3: Chạy test toàn bộ `interceptly_dio`**
Run: `cd packages/interceptly_dio && flutter test`
Expected: PASS
- [ ] **Step 4: Commit**
```bash
git add packages/interceptly_dio/
git commit -m "perf(dio): decouple response handler from body serialization and remove per-response compute"
```

---

### Task 9: Realtime Stream Hardening (Frame Truncation, Buffer Copy, Zero-Alloc Sizing & Session Bounds)

**Files:**
- Modify: `packages/interceptly/lib/src/model/realtime_frame.dart`
- Modify: `packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart`
- Modify: `packages/interceptly/lib/src/session/realtime_store.dart`
- Modify: `packages/interceptly_web_socket/lib/src/interceptly_web_socket_channel.dart`
- Test: `packages/interceptly/test/session/realtime_session_test.dart`
- Test: `packages/interceptly_web_socket/test/interceptly_web_socket_channel_test.dart`

**Interfaces:**
- `RealtimeTrafficCollector`:
  - Khi payload là `Uint8List`, copy an toàn bằng `Uint8List.fromList(payload)` để triệt tiêu buffer aliasing.
  - Truncate text và binary payload theo `settings.maxBodyBytes` trước khi lưu vào `RealtimeFrame`.
- `RealtimeFrame`:
  - Viết helper tính UTF-8 byte length không cấp phát thay cho `utf8.encode(text).length`.
- `RealtimeStore`:
  - Giới hạn tối đa 50 realtime session (LRU eviction khi session mới xuất hiện).
- `InterceptlyWebSocketChannel`:
  - Khi `uri == null`, gán fallback `Uri(scheme: 'ws', host: 'unknown-socket')` để luôn gọi `recordConnection`, bảo đảm có row trên UI.

- [ ] **Step 1: Viết test failing cho Frame Truncation, Buffer Copy và Fallback URI**
```dart
test('wrap without uri still records connection with fallback uri', () {
  final channel = InterceptlyWebSocketChannel(inner);
  expect(channel.uri, isNotNull);
  // Verify row created in memory index
});
test('binary payload is cloned and not aliased', () {
  final buffer = Uint8List.fromList([1, 2, 3]);
  collector.recordFrame(sessionId: 's', direction: FrameDirection.incoming, type: FrameType.binary, payload: buffer);
  buffer[0] = 99; // mutate app buffer
  expect(store.getFrames('s').first.binaryPayload![0], equals(1)); // retained original
});
```

- [ ] **Step 2: Triển khai các cải tiến Realtime Stream**
- [ ] **Step 3: Chạy test và commit**
Run: `cd packages/interceptly && flutter test test/session/realtime_session_test.dart && cd ../interceptly_web_socket && flutter test`
Expected: PASS
```bash
git add packages/interceptly/lib/ packages/interceptly_web_socket/lib/ packages/interceptly/test/ packages/interceptly_web_socket/test/
git commit -m "fix(realtime): prevent buffer aliasing, truncate frame payloads, and bound realtime sessions"
```

---

### Task 10: Dynamic Master Search, UI Notification Coalescing & Grouped Cache Invalidation

**Files:**
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart`
- Modify: `packages/interceptly/lib/src/session/master_search_controller.dart`
- Test: `packages/interceptly/test/session/master_search_dynamic_test.dart`

**Interfaces:**
- `InspectorSession`:
  - `_search.addListener`: gọi đồng thời `_invalidateGroupedCache()` và `notifyListeners()`.
  - `recordPending`: định tuyến qua `_scheduleCoalescedNotify()` thay vì gọi `notifyListeners()` tức thì để triệt tiêu UI thrashing.
- `MasterSearchController`:
  - Bổ sung `updateOrAddEntry(IndexEntry entry)`: cập nhật hoặc chèn entry mới vào kết quả tìm kiếm nếu khớp query.

- [ ] **Step 1: Viết test failing cho search invalidation và dynamic search updates**
- [ ] **Step 2: Cập nhật `InspectorSession` và `MasterSearchController`**
- [ ] **Step 3: Chạy test và commit**
Run: `cd packages/interceptly && flutter test test/session/master_search_dynamic_test.dart`
Expected: PASS
```bash
git add packages/interceptly/lib/src/session/ packages/interceptly/test/
git commit -m "perf(ui): invalidate grouped cache on search, coalesce pending notifications, and update search dynamically"
```

---

### Task 11: Xoá triệt để các Alias và Constructor thừa (Breaking Changes không @Deprecated)

**Files:**
- Modify: `packages/interceptly/lib/src/core/interceptly_controller.dart` (xoá `getFrames`)
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart` (xoá `getFrames`, xoá static `configure`)
- Modify: `packages/interceptly/lib/src/session/inspector_session_view.dart` (xoá `getFrames`)
- Modify: `packages/interceptly/lib/src/session/realtime_store.dart` (đổi `getFrames` thành `getRealtimeFrames`)
- Modify: `packages/interceptly/lib/src/session/memory_index.dart` (xoá `get(String id)`)
- Modify: `packages/interceptly/lib/src/export/har_exporter.dart` (xoá `fromRecords`)
- Modify: `packages/interceptly/lib/src/export/postman_exporter.dart` (xoá `fromRecords`)
- Modify: `packages/interceptly_http/lib/src/interceptly_http_client.dart` (xoá factory `wrap`)
- Modify: `packages/interceptly_web_socket/lib/src/interceptly_web_socket_channel.dart` (xoá static `wrap`)
- Modify: Toàn bộ caller, test, example và docs sử dụng các API trên.

**Interfaces:**
- Chuyển `getFrames` -> `getRealtimeFrames`.
- Chuyển `HarExporter.fromRecords` / `PostmanExporter.fromRecords` -> `toMap`.
- Chuyển `MemoryIndex.get` -> `byId`.
- Chuyển `.wrap(...)` -> constructor mặc định `InterceptlyHttpClient(...)` / `InterceptlyWebSocketChannel(...)`.
- Chuyển `InspectorSession.configure(settings)` -> `InspectorSession.instance.configureSession(settings)`.

- [ ] **Step 1: Xoá bỏ các method, constructor thừa**
- [ ] **Step 2: Cập nhật toàn bộ caller trong monorepo**
- [ ] **Step 3: Chạy analyze toàn bộ monorepo**
Run: `melos run analyze`
Expected: 0 warnings, 0 errors.
- [ ] **Step 4: Commit**
```bash
git add -u
git commit -m "refactor: remove redundant aliases and wrap constructors completely"
```

---

### Task 12: Thu hẹp SPI adapter trong `package:interceptly/adapter.dart`

**Files:**
- Modify: `packages/interceptly/lib/adapter.dart`
- Verify: `packages/interceptly_dio`, `packages/interceptly_http`, `packages/interceptly_chopper`, `packages/interceptly_web_socket`

**Interfaces:**
- `packages/interceptly/lib/adapter.dart` không còn export `RawCapture` và `InspectorSession`.

- [ ] **Step 1: Xoá export `RawCapture` và `InspectorSession` khỏi `packages/interceptly/lib/adapter.dart`**
- [ ] **Step 2: Kiểm tra adapter tests**
Đảm bảo các adapter test cần `InspectorSession.resetForTesting()` import trực tiếp từ `package:interceptly/interceptly.dart`.
- [ ] **Step 3: Chạy analyze và toàn bộ test suite**
Run: `melos run analyze && melos run test:core`
Expected: 0 errors, all PASS.
- [ ] **Step 4: Commit**
```bash
git add packages/interceptly/lib/adapter.dart packages/interceptly_*/test/
git commit -m "refactor(adapter): narrow SPI surface by unexporting RawCapture and InspectorSession"
```
