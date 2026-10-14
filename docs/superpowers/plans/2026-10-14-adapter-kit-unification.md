# Adapter Kit Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Đưa logic dùng chung của các adapter vào một "adapter kit" trong core, làm cho mọi adapter hành xử nhất quán (lỗi giả lập, cắt body, multipart, vòng đời capture), và có bộ conformance test chung chứng minh điều đó.

**Architecture:** Không đổi interface `HttpTrafficCollector`/`RealtimeTrafficCollector` (non-breaking cho người tự viết collector). Thêm các helper *composition* lên trên collector: `HttpCaptureScope` (vòng đời idempotent), `teeCapture` (tee stream có giới hạn + throttle), `summarizeMultipart`, `truncateUtf8`. Adapter chuyển sang dùng kit; một package dev `interceptly_adapter_testkit` chạy cùng bộ kịch bản cho Dio/http/Chopper.

**Tech Stack:** Dart >=3.5 <4.0, Flutter >=3.10, Melos 6, dio ^5, http ^1, chopper ^8, web_socket_channel >=2.4 <4, flutter_test.

**Spec:** Review kiến trúc adapter trong hội thoại 2026-10-14 (mục "Điểm chưa ổn" 1–4 và đề xuất P0–P3).

## Global Constraints

- Non-intrusive: capture lỗi phải nuốt (`guardCapture`), lỗi gốc của app rethrow nguyên; chỉ `SimulatedNetworkException` (hoặc subtype) được phép thoát ra.
- Non-breaking với end-user: constructor/factory public của `InterceptlyDioInterceptor`, `InterceptlyHttpClient`, `InterceptlyChopperInterceptor`, `InterceptlyWebSocketChannel` giữ nguyên chữ ký; getter `session`/`collector` trên adapter giữ nguyên.
- Non-breaking với người viết collector: không thêm/xoá/đổi chữ ký method của `HttpTrafficCollector` và `RealtimeTrafficCollector`.
- `melos run analyze` 0 warning/0 error; `melos run test:core` PASS sau mỗi task.
- Dùng `fvm flutter ...` nếu máy có fvm (repo có `.fvmrc`); lệnh dưới đây viết `flutter` cho gọn, chạy trong thư mục package tương ứng.
- Chỉ docstring `///`; không thêm `//` trừ khi giải thích quyết định load-bearing.
- Commit theo Conventional Commits như lịch sử repo (`feat(core): ...`, `refactor(dio): ...`).

## Review Focus

- App huỷ subscription giữa chừng khi đang tải response `http` → đúng **một** record `fail` với `CancellationException`, không có thêm `complete` (Task 3).
- Collector ném lỗi trong `completeResponse` → app vẫn nhận response nguyên vẹn (Task 1 kịch bản `collector-throws`, Task 2).
- `complete` rồi `fail` (hoặc ngược lại) được gọi trên cùng scope → chỉ lần đầu được ghi (Task 2).
- Text frame WebSocket chứa emoji/tiếng Việt bị cắt đúng ranh giới byte → không exception, chuỗi hợp lệ, `payloadSizeBytes` = kích thước gốc (Task 4, Task 9).
- Bật offline, app dùng `package:http` và `catch (e) on http.ClientException` → bắt được (Task 6, Task 7).

## Ghi chú hiệu chỉnh so với review

- Dòng "độ trễ sau response không ảnh hưởng app" ở `http` là **đúng thiết kế**: `http` đã throttle theo chunk khi stream, còn `completeResponse` chạy `unawaited` chỉ làm trễ thời điểm ghi record. Không sửa; Task 6 giữ nguyên hành vi này.
- `InterceptlySettings.shouldCapture` đã có sẵn bộ lọc URL toàn cục → **bỏ** ý tưởng `CaptureOptions` riêng cho từng adapter (YAGNI).
- Ngoài phạm vi: tách `NetworkConditioner`, sealed `FramePayload`, throttle cho Dio `ResponseType.stream`, tách `interceptly_core` khỏi UI. Đều đòi breaking change hoặc chưa có nhu cầu thực.

---

### Task 1: Package `interceptly_adapter_testkit` + conformance cho 3 adapter HTTP

Viết trước để ghim hành vi hiện tại; kịch bản đang hỏng được `skip` kèm số task sẽ sửa.

**Files:**
- Create: `packages/interceptly_adapter_testkit/pubspec.yaml` (`publish_to: none`; deps: `flutter`, `flutter_test`, `interceptly: path ../interceptly`)
- Create: `packages/interceptly_adapter_testkit/lib/interceptly_adapter_testkit.dart`
- Create: `packages/interceptly_adapter_testkit/lib/src/recording_collector.dart`
- Create: `packages/interceptly_adapter_testkit/lib/src/http_adapter_harness.dart`
- Create: `packages/interceptly_adapter_testkit/lib/src/http_conformance.dart`
- Modify: `packages/interceptly_{dio,http,chopper}/pubspec.yaml` (dev_dependency `interceptly_adapter_testkit: path ../interceptly_adapter_testkit`)
- Test: `packages/interceptly_{dio,http,chopper}/test/conformance_test.dart`

**Interfaces:**
- Produces:
  - `class RecordingHttpTrafficCollector implements HttpTrafficCollector` — fields `bool simulateOffline`, `bool throwOnStart`, `bool throwOnComplete`, `bool throwOnFail`; `List<RecordedHttpCall> get calls`.
  - `sealed class RecordedHttpCall` với `RecordedStart(method, uri, headers, bodyBytes)`, `RecordedComplete(context, statusCode, headers, bodyBytes)`, `RecordedFail(context, error, errorType, statusCode)`.
  - `sealed class StubResponse` với `StubResponse.ok(int statusCode, {Map<String,String> headers, List<int> body})` và `StubResponse.transportError()`.
  - `class HarnessOutcome { int? statusCode; List<int>? body; Object? error; }`
  - `abstract interface class HttpAdapterHarness { Future<HarnessOutcome> send({required String method, required Uri uri, Map<String,String> headers, List<int>? body, required StubResponse stub, required HttpTrafficCollector collector}); bool isNativeTransportError(Object error); bool isNativeSimulatedError(Object error); }`
  - `void runHttpAdapterConformance(String adapterName, HttpAdapterHarness Function() createHarness, {Set<String> skip = const {}})` — `skip` là tập id kịch bản.

Kịch bản (id → kỳ vọng):

| id | Điều kiện | Kỳ vọng |
|---|---|---|
| `success` | `ok(200, body: '{"a":1}')` | app nhận 200 + body; calls = [Start, Complete(200, body)] |
| `http-error` | `ok(404)` | calls = [Start, Complete(404)], không có Fail (app có thể nhận error — Dio) |
| `transport-error` | `transportError()` | `outcome.error` thoả `isNativeTransportError`; calls = [Start, Fail] |
| `offline` | `simulateOffline = true` | `outcome.error` thoả `isNativeSimulatedError` **và** `is SimulatedNetworkException`; không gọi transport |
| `collector-throws` | `throwOnStart/Complete/Fail = true` | app nhận 200 + body như `success` |
| `request-body` | POST body `'hello'` | `RecordedStart.bodyBytes` = utf8 `'hello'` |

- [ ] **Step 1: Viết testkit + 3 harness** — http dùng `MockClient` của `package:http/testing.dart`; Chopper dùng `ChopperClient(client: MockClient(...), interceptors: [adapter])`; Dio dùng `HttpClientAdapter` giả trả `ResponseBody.fromBytes`. `isNativeSimulatedError`: http/Chopper → `e is http.ClientException`; Dio → `e is DioException && e.type == DioExceptionType.connectionError`.

- [ ] **Step 2: Chạy, xác nhận chỉ `offline` hỏng ở http và Chopper**

Run: `flutter test test/conformance_test.dart` trong từng package.
Expected: Dio PASS hết; http và Chopper FAIL đúng `offline` (lỗi là `SimulatedNetworkException` trần, không phải `ClientException`).

- [ ] **Step 3: Đánh dấu `skip: {'offline'}` cho http và Chopper, ghi chú "Task 6"/"Task 7"; chạy lại → PASS**

- [ ] **Step 4: Commit** — `test(testkit): add shared HTTP adapter conformance suite`

---

### Task 2: `HttpCaptureScope` trong core

**Files:**
- Modify: `packages/interceptly/lib/src/adapter/http_request_context.dart` (thêm `copyWith`)
- Create: `packages/interceptly/lib/src/adapter/http_capture_scope.dart`
- Create: `packages/interceptly/test/helpers/recording_http_collector.dart`
- Test: `packages/interceptly/test/adapter/http_capture_scope_test.dart`

**Interfaces:**
- Consumes: `HttpTrafficCollector`, `HttpRequestContext`. Test của core dùng một fake cục bộ `test/helpers/recording_http_collector.dart` có cùng API với `RecordingHttpTrafficCollector` của Task 1 (không thêm testkit làm dev_dependency của core để tránh vòng phụ thuộc core ↔ testkit).
- Produces:
  - `HttpRequestContext copyWith({String? method, Uri? uri, Map<String,String>? requestHeaders, Uint8List? requestBodyBytes, String? requestContentType})` — `id`, `startedAt` không đổi được.
  - `final class HttpCaptureScope`:
    - `static Future<HttpCaptureScope> begin(HttpTrafficCollector collector, {required String method, required Uri uri, Map<String,String>? headers, Uint8List? bodyBytes, String? contentType})` — chỉ rethrow `SimulatedNetworkException`; mọi lỗi khác → scope inactive.
    - `factory HttpCaptureScope.fromContext(HttpTrafficCollector collector, HttpRequestContext? context)` — dùng khi context đã được tạo ở callback khác (Dio).
    - `HttpRequestContext? get context`, `bool get isActive`, `bool get isSettled`.
    - `void amendRequest({String? method, Uri? uri, Map<String,String>? headers, Uint8List? bodyBytes, String? contentType})`
    - `Future<void> complete({required int statusCode, Map<String,String>? headers, Uint8List? bodyBytes, String? contentType})`
    - `void fail(Object error, {String? errorType, String? errorMessage, int? statusCode, Map<String,String>? responseHeaders, Uint8List? responseBodyBytes})`
  - Bất biến: `complete`/`fail` không bao giờ ném; lần gọi đầu tiên đánh dấu `isSettled = true` **trước** khi await; mọi lần gọi sau là no-op; scope inactive thì mọi method là no-op.

- [ ] **Step 1: Viết test fail**

```dart
test('first settle wins', () async {
  final c = RecordingHttpTrafficCollector();
  final s = await HttpCaptureScope.begin(c, method: 'GET', uri: Uri.parse('https://x'));
  await s.complete(statusCode: 200);
  s.fail(StateError('late'));
  expect(c.calls.whereType<RecordedComplete>(), hasLength(1));
  expect(c.calls.whereType<RecordedFail>(), isEmpty);
});
test('offline rethrows', () async {
  final c = RecordingHttpTrafficCollector()..simulateOffline = true;
  expect(HttpCaptureScope.begin(c, method: 'GET', uri: Uri.parse('https://x')),
      throwsA(isA<SimulatedNetworkException>()));
});
test('start throws generic -> inactive, no throw', () async {
  final c = RecordingHttpTrafficCollector()..throwOnStart = true;
  final s = await HttpCaptureScope.begin(c, method: 'GET', uri: Uri.parse('https://x'));
  expect(s.isActive, isFalse);
  await s.complete(statusCode: 200);
  expect(c.calls.whereType<RecordedComplete>(), isEmpty);
});
test('complete swallows collector error', () async {
  final c = RecordingHttpTrafficCollector()..throwOnComplete = true;
  final s = await HttpCaptureScope.begin(c, method: 'GET', uri: Uri.parse('https://x'));
  await expectLater(s.complete(statusCode: 200), completes);
});
test('amendRequest keeps id and startedAt', () async {
  final c = RecordingHttpTrafficCollector();
  final s = await HttpCaptureScope.begin(c, method: 'GET', uri: Uri.parse('https://x'));
  final before = s.context!;
  s.amendRequest(headers: {'x-sent': '1'});
  expect(s.context!.id, before.id);
  expect(s.context!.startedAt, before.startedAt);
  await s.complete(statusCode: 200);
  expect((c.calls.last as RecordedComplete).context.requestHeaders, {'x-sent': '1'});
});
```

- [ ] **Step 2: Run** `flutter test test/adapter/http_capture_scope_test.dart` → FAIL (chưa có file).
- [ ] **Step 3: Implement** theo Interfaces; lỗi debug in qua `debugPrint` khi `kDebugMode`, cùng prefix `[Interceptly]`.
- [ ] **Step 4: Run** lại → PASS; chạy `flutter test test/adapter` → PASS.
- [ ] **Step 5: Commit** — `feat(core): add HttpCaptureScope lifecycle helper`

---

### Task 3: `teeCapture` — tee stream có giới hạn + throttle

Chuyển logic `_teeResponseStream` của `interceptly_http` vào core, tổng quát hoá.

**Files:**
- Create: `packages/interceptly/lib/src/capture/stream_capture.dart`
- Test: `packages/interceptly/test/capture/stream_capture_test.dart`

**Interfaces:**
- Produces:
  - `final class CappedBytesBuilder { CappedBytesBuilder(int maxBytes); void add(List<int> chunk); int get totalBytes; bool get isTruncated; Uint8List? toBytesOrNull(); }` — `maxBytes <= 0` nghĩa là không giới hạn; không bao giờ giữ quá `maxBytes`.
  - `Stream<List<int>> teeCapture(Stream<List<int>> source, {required int maxBytes, Duration Function(int chunkBytes)? chunkDelay, required void Function(Uint8List? captured) onDone, required void Function(Object error, StackTrace stackTrace, Uint8List? captured) onError, required void Function(Uint8List? captured) onCancel})`
  - Bất biến: forward mọi chunk nguyên vẹn, đúng thứ tự; hỗ trợ pause/resume/cancel; đúng **một** trong ba callback được gọi, tối đa một lần; lỗi trong callback bị nuốt.

- [ ] **Step 1: Viết test fail** — 5 test:
  - `forwards all chunks unchanged`: source `[[1,2],[3]]` → listener nhận `[[1,2],[3]]`, `onDone` nhận `[1,2,3]`.
  - `caps captured bytes`: `maxBytes: 4`, source `[[1,2,3],[4,5,6]]` → listener nhận đủ 6 byte; captured = `[1,2,3,4]`.
  - `cancel reports once`: listen rồi `cancel()` sau chunk đầu → `onCancel` gọi 1 lần, `onDone`/`onError` 0 lần.
  - `error reports once and forwards`: source phát lỗi → listener nhận lỗi; `onError` 1 lần; huỷ sau đó không gọi `onCancel`.
  - `chunkDelay applied` (dùng `fake_async`): `chunkDelay: (_) => 100ms` → chunk chưa tới trước 100ms, tới sau 100ms.
- [ ] **Step 2: Run** `flutter test test/capture/stream_capture_test.dart` → FAIL.
- [ ] **Step 3: Implement** bằng cách bê thân `_teeResponseStream` hiện tại ([interceptly_http_client.dart](../../../packages/interceptly_http/lib/src/interceptly_http_client.dart)) thay `captureBuffer` bằng `CappedBytesBuilder`, `session.throughputDelayForChunk` bằng `chunkDelay`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** — `feat(core): extract bounded tee stream capture`

---

### Task 4: `summarizeMultipart` + `truncateUtf8`

**Files:**
- Create: `packages/interceptly/lib/src/capture/multipart_summary.dart`
- Modify: `packages/interceptly/lib/src/capture/body_bytes.dart` (thêm `truncateUtf8`)
- Test: `packages/interceptly/test/capture/multipart_summary_test.dart`, `packages/interceptly/test/capture/body_bytes_test.dart`

**Interfaces:**
- Produces:
  - `class MultipartFileInfo { const MultipartFileInfo({required String field, String? filename, String? contentType, int? length}); }`
  - `Uint8List summarizeMultipart({Iterable<MapEntry<String,String>> fields = const [], Iterable<MultipartFileInfo> files = const []})` — format chuẩn (giữ format của `http` hiện tại):
    - mỗi field: `[field] <key>=<value>`
    - mỗi file: `[file] <field>: <filename ?? 'blob'> (<contentType ?? 'application/octet-stream'>[, <length> bytes])`
    - nối bằng `\n`
  - `String truncateUtf8(String text, int maxBytes)` — `maxBytes <= 0` hoặc vừa đủ → trả nguyên; ngược lại cắt theo byte UTF-8, lùi điểm cắt khi `(bytes[cut] & 0xC0) == 0x80` để không tách code point, decode lại.

- [ ] **Step 1: Viết test fail**

```dart
expect(utf8.decode(summarizeMultipart(
  fields: [const MapEntry('a', '1')],
  files: [const MultipartFileInfo(field: 'f', filename: 'x.png', contentType: 'image/png', length: 10)],
)), '[field] a=1\n[file] f: x.png (image/png, 10 bytes)');
expect(utf8.decode(summarizeMultipart(files: [const MultipartFileInfo(field: 'f')])),
  '[file] f: blob (application/octet-stream)');
expect(truncateUtf8('héllo', 2), 'h');      // 'é' = 2 byte, không bị tách
expect(truncateUtf8('ab😀', 5), 'ab');      // emoji 4 byte
expect(truncateUtf8('abc', 0), 'abc');
expect(truncateUtf8('Việt', 100), 'Việt');
```

- [ ] **Step 2: Run** cả hai file test → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** — `feat(core): add multipart summary and utf8-safe truncation helpers`

---

### Task 5: Library SPI `adapter.dart`, inject session vào collector, deprecate interface thừa

**Files:**
- Create: `packages/interceptly/lib/adapter.dart`
- Modify: `packages/interceptly/lib/interceptly.dart`
- Modify: `packages/interceptly/lib/src/adapter/http_traffic_collector.dart:58-64`
- Modify: `packages/interceptly/lib/src/adapter/realtime_traffic_collector.dart` (constructor `DefaultRealtimeTrafficCollector`)
- Modify: `packages/interceptly/lib/src/adapter/network_capture_adapter.dart`
- Modify: `packages/interceptly/README.md` (thêm mục "Writing an adapter")
- Test: `packages/interceptly/test/adapter/traffic_collectors_test.dart`

**Interfaces:**
- Produces:
  - `package:interceptly/adapter.dart` export: `HttpTrafficCollector`, `DefaultHttpTrafficCollector`, `RealtimeTrafficCollector`, `DefaultRealtimeTrafficCollector`, `HttpRequestContext`, `HttpCaptureScope`, `teeCapture`, `CappedBytesBuilder`, `summarizeMultipart`, `MultipartFileInfo`, `truncateUtf8`, `encodeBodyBytes`, `normalizeHeaders`, `guardCapture`, `guardCaptureAsync`, `headerValue`, `SimulatedNetworkException`, `FrameDirection`, `FrameType`, `RequestId`, `InspectorSession`.
  - `interceptly.dart` vẫn export y như cũ (non-breaking) và **không** export các symbol mới của Task 2–4 (chúng chỉ có trong `adapter.dart`).
  - `DefaultHttpTrafficCollector({InspectorSession? session})`, `DefaultRealtimeTrafficCollector({InspectorSession? session})` — getter `session` trả `_session ?? InspectorSession.instance`, resolve **lúc gọi** (để `resetForTesting` vẫn đúng).
  - `@Deprecated('Not consumed polymorphically; will be removed in 3.0.') ` trên `HttpCaptureAdapter`, `RealtimeCaptureAdapter`.

- [ ] **Step 1: Viết test fail**

```dart
test('injected session is used', () async {
  final custom = InspectorSession(settings: const InterceptlySettings());
  expect(DefaultHttpTrafficCollector(session: custom).session, same(custom));
  expect(DefaultRealtimeTrafficCollector(session: custom).session, same(custom));
});
test('default resolves singleton lazily', () async {
  final c = DefaultHttpTrafficCollector();
  await InspectorSession.resetForTesting();
  expect(c.session, same(InspectorSession.instance));
});
```

- [ ] **Step 2: Run** `flutter test test/adapter/traffic_collectors_test.dart` → FAIL (named param chưa có).
- [ ] **Step 3: Implement**; viết README mục "Writing an adapter" ≤ 40 dòng với ví dụ `HttpCaptureScope.begin/complete/fail`.
- [ ] **Step 4: Run** `flutter test test/adapter && flutter analyze` → PASS (analyze sẽ báo deprecated ở 4 adapter — chấp nhận tạm, Task 6–9 gỡ).
- [ ] **Step 5: Commit** — `feat(core): add adapter SPI library and session injection for collectors`

---

### Task 6: Migrate `interceptly_http`

**Files:**
- Modify: `packages/interceptly_http/lib/src/interceptly_http_client.dart`
- Create: `packages/interceptly_http/lib/src/simulated_client_exception.dart`
- Modify: `packages/interceptly_http/lib/interceptly_http.dart` (export exception)
- Test: `packages/interceptly_http/test/http_client_test.dart`, `packages/interceptly_http/test/conformance_test.dart`

**Interfaces:**
- Consumes: `HttpCaptureScope` (Task 2), `teeCapture` (Task 3), `summarizeMultipart`/`MultipartFileInfo` (Task 4), `package:interceptly/adapter.dart` (Task 5).
- Produces: `class InterceptlySimulatedClientException extends http.ClientException implements SimulatedNetworkException { InterceptlySimulatedClientException(String message, Uri? uri); }`

- [ ] **Step 1: Bỏ `skip: {'offline'}` trong `conformance_test.dart`; thêm test**

```dart
test('offline surfaces as ClientException', () async {
  final c = RecordingHttpTrafficCollector()..simulateOffline = true;
  final client = InterceptlyHttpClient(MockClient((_) async => http.Response('', 200)), c);
  await expectLater(client.get(Uri.parse('https://x')),
      throwsA(allOf(isA<http.ClientException>(), isA<SimulatedNetworkException>())));
});
```

- [ ] **Step 2: Run** `flutter test` → FAIL đúng 2 test trên.
- [ ] **Step 3: Implement** — `send()`: `HttpCaptureScope.begin` trong `try`, `on SimulatedNetworkException catch (e)` → `throw InterceptlySimulatedClientException(e.message, request.url)`; lỗi transport → `scope.fail(e)` + rethrow; response stream → `teeCapture(maxBytes: session.settings.maxBodyBytes, chunkDelay: session.throughputDelayForChunk, onDone: (b) => unawaited(scope.complete(...)), onError: (e, _, b) => scope.fail(e, ...), onCancel: (b) => scope.fail('CancellationException', errorType: 'CancellationException', errorMessage: 'Stream subscription was canceled by client.', ...))`; multipart → `summarizeMultipart`. Xoá `_teeResponseStream`, `_summarizeMultipart`, bỏ `implements HttpCaptureAdapter` (giữ getter `session`, `collector`).
- [ ] **Step 4: Run** `flutter test && flutter analyze` → PASS, 0 deprecation warning trong package.
- [ ] **Step 5: Commit** — `refactor(http): adopt adapter kit and surface simulated offline as ClientException`

---

### Task 7: Migrate `interceptly_chopper`

**Files:**
- Modify: `packages/interceptly_chopper/lib/src/interceptly_chopper_interceptor.dart`
- Create: `packages/interceptly_chopper/lib/src/simulated_client_exception.dart` (cùng định nghĩa như Task 6; chấp nhận lặp ~10 dòng để Chopper không phụ thuộc `interceptly_http`)
- Modify: `packages/interceptly_chopper/lib/interceptly_chopper.dart`
- Test: `packages/interceptly_chopper/test/chopper_interceptor_test.dart`, `packages/interceptly_chopper/test/conformance_test.dart`

**Interfaces:**
- Consumes: `HttpCaptureScope.begin/amendRequest/complete/fail` (Task 2).
- Produces: `InterceptlySimulatedClientException` (export từ `interceptly_chopper`).

- [ ] **Step 1: Bỏ skip `offline`; thêm test** `offline surfaces as ClientException` tương tự Task 6 qua `ChopperClient`.
- [ ] **Step 2: Run** → FAIL đúng các test đó.
- [ ] **Step 3: Implement** — thay khối `try/on/catch` + dựng lại `HttpRequestContext` bằng `scope.amendRequest(method: sent?.method, uri: sent?.url, headers: sentHeaders, bodyBytes: sentBody, contentType: headerValue(sentHeaders, 'content-type'))` rồi `await scope.complete(...)`. Bỏ `implements HttpCaptureAdapter`.
- [ ] **Step 4: Run** `flutter test && flutter analyze` → PASS.
- [ ] **Step 5: Commit** — `refactor(chopper): adopt adapter kit and surface simulated offline as ClientException`

---

### Task 8: Migrate `interceptly_dio`

**Files:**
- Modify: `packages/interceptly_dio/lib/src/interceptly_dio_interceptor.dart`
- Test: `packages/interceptly_dio/test/interceptly_dio_interceptor_test.dart`, `packages/interceptly_dio/test/dio_onerror_test.dart`

**Interfaces:**
- Consumes: `HttpCaptureScope.begin/fromContext` (Task 2), `summarizeMultipart` (Task 4).
- Produces: keys trong `options.extra`: `interceptly_scope` (`HttpCaptureScope`), `interceptly_started_at` (`DateTime`) — thay cho `interceptly_http_context`/`interceptly_req_bytes`.

- [ ] **Step 1: Viết test fail**

```dart
test('fallback context keeps real start time', () async {
  // collector.throwOnStart = true → không có scope active, nhưng started_at vẫn được ghi
  // stub adapter trễ 50ms rồi trả 500
  // kỳ vọng: RecordedComplete/RecordedFail có duration >= 50ms (dùng durationMs hoặc context.startedAt)
});
test('FormData summary uses shared format', () async {
  // POST FormData.fromMap({'a': '1', 'f': MultipartFile.fromBytes([1,2,3], filename: 'x.bin')})
  // kỳ vọng RecordedStart.bodyBytes decode == '[field] a=1\n[file] f: x.bin (application/octet-stream, 3 bytes)'
});
```

Cập nhật các test cũ đang assert format `a=1&b=2` sang format mới.

- [ ] **Step 2: Run** `flutter test` → FAIL đúng các test trên.
- [ ] **Step 3: Implement**
  - `onRequest`: luôn set `extra['interceptly_started_at'] = DateTime.now()` trước; `HttpCaptureScope.begin` → lưu vào `extra['interceptly_scope']`; `on SimulatedNetworkException` → `handler.reject(DioException(type: connectionError, error: e))` như cũ.
  - `onResponse`/`onError`: lấy scope từ extra; nếu không có và `session.isEnabled` → `HttpCaptureScope.fromContext(collector, HttpRequestContext(id: RequestId.generate(), ..., startedAt: extra['interceptly_started_at'] ?? DateTime.now()))`. `badResponse` → `scope.complete`, còn lại → `scope.fail`. Luôn xoá 2 key trong `finally`.
  - `onError` đổi kiểu trả về thành `Future<void>`; xoá `_reqBytesKey`; FormData → `summarizeMultipart` với `MultipartFile.length`.
  - Bỏ `implements HttpCaptureAdapter`.
- [ ] **Step 4: Run** `flutter test && flutter analyze` → PASS, conformance vẫn PASS.
- [ ] **Step 5: Commit** — `refactor(dio): adopt adapter kit, fix fallback duration and multipart format`

---

### Task 9: Sửa `interceptly_web_socket`

**Files:**
- Modify: `packages/interceptly_web_socket/lib/src/interceptly_web_socket_channel.dart`
- Test: `packages/interceptly_web_socket/test/interceptly_web_socket_channel_test.dart`

**Interfaces:**
- Consumes: `truncateUtf8` (Task 4), `DefaultRealtimeTrafficCollector` (Task 5).
- Produces: hằng `static final Uri unknownUri = Uri(scheme: 'ws', host: 'unknown')` trên `InterceptlyWebSocketChannel` — dùng khi `uri == null`.

- [ ] **Step 1: Viết test fail** (dùng một `RecordingRealtimeCollector` cục bộ trong file test)

```dart
test('text frame truncated by utf8 bytes and reports original size', () {
  // settings.maxBodyBytes = 4; gửi 'ab😀c' (7 byte)
  // kỳ vọng payload == 'ab', payloadSizeBytes == 7
});
test('binary frame reports original size', () {
  // maxBodyBytes = 2; gửi Uint8List.fromList([1,2,3]) → payload [1,2], payloadSizeBytes == 3
});
test('wrap without uri still records a connection', () {
  // InterceptlyWebSocketChannel.wrap(inner) → recordConnection(uri: InterceptlyWebSocketChannel.unknownUri)
});
```

Cập nhật test cũ đang assert cắt theo `text.length`.

- [ ] **Step 2: Run** `flutter test` → FAIL đúng 3 test.
- [ ] **Step 3: Implement** — `_truncateText` dùng `truncateUtf8`; `_recordFrame` tính kích thước gốc (`utf8.encode(text).length` hoặc `bytes.length`) và truyền `payloadSizeBytes`; constructor gọi `recordConnection` với `uri ?? unknownUri`. Bỏ `implements RealtimeCaptureAdapter` (giữ getter).
- [ ] **Step 4: Run** `flutter test --exclude-tags=stress && flutter analyze` → PASS; sau đó `flutter test --tags=stress` → PASS.
- [ ] **Step 5: Commit** — `fix(web_socket): utf8-safe truncation, original payload size, record unknown-uri connections`

---

### Task 10: Đồng bộ version & chuẩn bị publish

**Files:**
- Modify: `packages/interceptly/pubspec.yaml` (`version: 2.1.0`)
- Modify: `packages/interceptly_{dio,http,chopper,web_socket}/pubspec.yaml` (`version: 2.1.0`; `interceptly: ^2.1.0` thay `path:`; thêm `homepage`, `repository`, `issue_tracker` giống core; WS bỏ `publish_to: "none"`)
- Modify/Create: `CHANGELOG.md` của 5 package
- Modify: `melos.yaml` (thêm `command.version: { linkToCommits: true, workspaceChangelog: false }`)

**Interfaces:**
- Consumes: toàn bộ Task 1–9 đã merge.
- Produces: lockstep version `2.1.0` cho core + 4 adapter; testkit giữ `publish_to: none`.

- [ ] **Step 1: Sửa pubspec + CHANGELOG** — CHANGELOG core: "Added `package:interceptly/adapter.dart`, `HttpCaptureScope`, `teeCapture`, `summarizeMultipart`, `truncateUtf8`; collectors accept `session`; deprecated `HttpCaptureAdapter`/`RealtimeCaptureAdapter`." Adapter: liệt kê thay đổi hành vi (offline → `ClientException`, multipart format, WS truncation).
- [ ] **Step 2: Bootstrap** — Run: `melos bootstrap` → `pubspec_overrides.yaml` được sinh lại, resolve thành công.
- [ ] **Step 3: Verify toàn repo** — Run: `melos run analyze && melos run test:core` → 0 issue, PASS.
- [ ] **Step 4: Dry-run publish** — Run: `flutter pub publish --dry-run` trong từng package publishable. Expected: không có error; chỉ warning liên quan `pubspec_overrides.yaml` / dependency chưa có trên pub.dev (với adapter, trước khi core 2.1.0 được publish).
- [ ] **Step 5: Commit** — `chore(release): align packages to 2.1.0 with hosted interceptly dependency`
