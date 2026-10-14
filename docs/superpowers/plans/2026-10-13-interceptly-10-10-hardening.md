# Interceptly 10/10 Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Đưa interceptly monorepo từ ~6.6/10 lên 10/10 theo rubric review (production-safe, zero-footgun, chứng minh bằng test/metric).

**Architecture:** Giữ hướng `adapters -> core`, tách `InspectorSession` God Object thành facade + pipeline/store/loader, thêm generation fence + coalesce notify, siết export/replay/security, chuẩn hóa adapters semantics, fix UI rebuild/virtualization.

**Tech Stack:** Flutter >=3.10, Dart >=3.5 <4.0, Melos, flutter_test + fake_async, `compute`/isolate, path_provider temp files.

**Spec:** 10 báo cáo review song song (kiến trúc 6.0, session 6.5, adapters 7.5, UI 6.5, export 6.5, quality 7.5, perf 7.5, security 4.0, testing 7.5, DX 6.5). Source paths dưới `packages/interceptly/`, `packages/interceptly_{dio,http,chopper,web_socket}/`.

## Global Constraints

- Không làm đổi behavior request gốc của host app (non-intrusive); mọi capture lỗi phải nuốt qua `guardCapture`, error gốc phải rethrow nguyên.
- Không commit/merge/push; mọi thay đổi để uncommitted cho user review.
- Chỉ dùng docstring, không thêm inline `#`/`//` comments trừ khi giải thích quyết định load-bearing.
- Mọi task chạy `flutter analyze` + `flutter test` liên quan trước khi coi là xong.
- Không đoán version/pubspec; verify bằng đọc file thật.

## Review Focus

- Burst 1000 captures khi `clear()` xen giữa -> mong đợi index trống, không hồi sinh entry stale, không đọc nhầm body cross-request.
- `InterceptlySettings(maxEntries: 0)` -> mong đợi clamp về 1, không RangeError runtime.
- String body Dio >50KB -> mong đợi capture đủ, không mất thầm lặng.
- Paste cURL export vào shell với method bẩn (`GET; rm -rf`) -> mong đợi bị whitelist chặn, không RCE.
- Replay POST lên production khi đang gắn Authorization -> mong đợi confirm dialog + block loopback/private IP.
- Export HAR/Postman của request có `Authorization: Bearer` -> mong đợi redact hoặc warn + xóa temp sau share.

---

### Task 1: P0 Security defaults + redaction mở rộng

**Files:**
- Modify: `packages/interceptly/lib/src/model/interceptly_settings.dart:1-93`
- Modify: `packages/interceptly/lib/src/capture/capture_guard.dart:40-65`
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart:344-381,397-453`
- Modify: `packages/interceptly/README.md`, `README.md` (docs drift)
- Test: `packages/interceptly/test/session/security_defaults_test.dart` (new)

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `InterceptlySettings(redactedHeaders, redactedQueryParams, bodyRedactor)` canonical defaults; `CaptureGuard.sanitizeUrl(String) -> String` dùng chung cho session + exporters.

- [x] **Step 1: Write failing tests** covering default `redactedHeaders` non-empty (`authorization,cookie,set-cookie,x-api-key`), `sanitizeUrl` mask `?token/api_key/password`, `bodyRedactor` hook được gọi trước persist.
- [x] **Step 2: Run to verify fail** — Run: `flutter test test/session/security_defaults_test.dart` Expected: FAIL (default `{}`).
- [x] **Step 3: Implement** `redactedHeaders` default 4 headers, thêm `redactedQueryParams` default + `bodyRedactor` typedef, `sanitizeUrl` dùng chung, gọi trong `record/recordPending` trước isolate.
- [x] **Step 4: Fix docs** — sửa Features bullet "Safe by Default", bảng config, quickstart warn PII.
- [x] **Step 5: Verify** — Run: `flutter analyze && flutter test test/session/security_defaults_test.dart test/stress/memory_index_redaction_stress_test.dart` Expected: PASS. Để changes uncommitted.

### Task 2: Session generation fence + clamp + inFlight fix

**Files:**
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart:233-239,383-390,786-812`
- Modify: `packages/interceptly/lib/src/session/memory_index.dart:46-101`
- Modify: `packages/interceptly/lib/src/session/ring_buffer.dart:43`, `bounded_event_queue.dart:13`
- Test: `packages/interceptly/test/session/clear_generation_test.dart` (new)

**Interfaces:**
- Consumes: Task 1 settings.
- Produces: `InspectorSession` generation-fenced `record/clear`; `MemoryIndex` clamp `maxEntries>=1`.

- [x] **Step 1: Write failing tests** — burst 100 record, `clear()` giữa chừng, assert index trống + `loadDetail` không đọc nhầm offset cũ; `maxEntries:0` không throw.
- [x] **Step 2: Run to verify fail** — Run: `flutter test test/session/clear_generation_test.dart` Expected: FAIL (hồi sinh entry).
- [x] **Step 3: Implement** `int _generation`, tag `_sendCapture`, drop entry khác generation trong `_onEntryReady`, reset `_inFlight=0` sau clear, bọc `send` try/catch, clamp capacities.
- [x] **Step 4: Verify** — Run: `flutter test test/session/ test/stress/session_eviction_lifecycle_stress_test.dart` Expected: PASS.

### Task 3: Temp file lifecycle + disk cap + multi-instance purge

**Files:**
- Modify: `packages/interceptly/lib/src/session/writer_isolate.dart:170-192`
- Modify: `packages/interceptly/lib/src/session/body_store.dart:23-134`
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart:203-214,815-844`
- Test: `packages/interceptly/test/session/temp_lifecycle_test.dart` (new)

**Interfaces:**
- Consumes: Task 2 generation.
- Produces: `BodyStore` total-bytes cap + mtime-gated purge; `WriterIsolate.dispose` fallback delete từ main.

- [x] **Step 1: Write failing tests** — dispose khi isolate bận vẫn xóa file; vượt 100MB tự rotate; session B live không bị session A purge.
- [x] **Step 2: Run to verify fail** — Expected: FAIL (leak / xóa nhầm).
- [x] **Step 3: Implement** lưu `filePath` ở main, delete sau kill; track `_currentOffset` + rotate; purge chỉ file mtime >24h; thêm `memoryOnly/persistToDisk:false` option + docs.
- [x] **Step 4: Verify** — Run: `flutter test test/session/temp_lifecycle_test.dart test/session/temp_cleanup_test.dart` Expected: PASS.

### Task 4: Adapters semantics + Dio compute + http resume + WS error path

**Files:**
- Modify: `packages/interceptly_dio/lib/src/interceptly_dio_interceptor.dart:30-37,56-96,198-278`
- Modify: `packages/interceptly_http/lib/src/interceptly_http_client.dart:53-81,174-254`
- Modify: `packages/interceptly_chopper/lib/src/interceptly_chopper_interceptor.dart:55-127`
- Modify: `packages/interceptly_web_socket/lib/src/interceptly_web_socket_channel.dart:104-213`
- Test: `packages/interceptly_dio/test/dio_onerror_test.dart` (new), extend http/chopper/ws tests

**Interfaces:**
- Consumes: Task 1 sanitize + Task 2 session.
- Produces: Unified `errorType` policy (chỉ transport/cancel/timeout là error), duration đo sau simulation ở cả 3 adapters.

- [x] **Step 1: Write failing tests** — Dio `onError(connectionTimeout/cancel/badResponse)` passthrough + `hasError`; Dio String >50KB capture đủ; http cancel giữa throughput-delay không unhandled; WS `handleError`/ready-fail close connection; 404 cùng semantics 3 adapters.
- [x] **Step 2: Run to verify fail** — Run: `flutter test` trong 4 adapter packages Expected: FAIL ít nhất Dio compute + WS leak.
- [x] **Step 3: Implement** top-level `_utf8Encode` helper thay `compute(utf8.encode)`; đưa simulation ra ngoài guard ở Dio; guard `sub.resume()` (try/catch + `isPaused` + closed check); WS `handleError` record + close, `ready.onError` close, thêm `ByteData` branch, forward-trước-record-sau ở `sink.add`; thống nhất `errorType` + duration sau simulation; `extra.remove(_reqBytesKey)` sau record; truncate WS frame theo `maxBodyBytes`.
- [x] **Step 4: Verify** — Run: `flutter test` 4 adapters + `dart analyze` Expected: PASS.

### Task 5: Export hardening (cURL/HAR/Postman) + share cleanup + replay SSRF guard

**Files:**
- Modify: `packages/interceptly/lib/src/export/curl_generator.dart:14-52`
- Modify: `packages/interceptly/lib/src/export/har_exporter.dart:30-89`
- Modify: `packages/interceptly/lib/src/export/postman_exporter.dart:36-133`
- Modify: `packages/interceptly/lib/src/ui/detail/replay_handler.dart:92-308`
- Modify: `packages/interceptly/lib/src/ui/detail/share_handler.dart:125-240`
- Modify: `packages/interceptly/lib/src/share/interceptly_share.dart:20-46`
- Test: `packages/interceptly/test/export/export_hardening_test.dart` (new)

**Interfaces:**
- Consumes: Task 1 sanitize/redact.
- Produces: `CurlGenerator` method-whitelisted; `HarExporter/PostmanExporter` redact-aware; `ReplayHandler` SSRF-guarded; `ShareHandler` temp-cleanup.

- [x] **Step 1: Write failing tests** — method `GET; rm` bị reject; HAR có `blocked/dns/connect/ssl/cache/pages/queryString`, status<=0 guarded; Postman giữ port + warn multipart rỗng; export Authorization bị redact khi `redactOnExport:true`; replay `file://`/169.254 bị block; share xong file bị xóa.
- [x] **Step 2: Run to verify fail** — Expected: FAIL.
- [x] **Step 3: Implement** method whitelist + CRLF strip; HAR bổ sung fields + `toUtc`; Postman giữ port + document strip userinfo; áp `redactHeaders/sanitizeUrl` trước export + confirm dialog PII + `try/finally delete`; replay enforce http/https + IP blocklist + confirm non-idempotent + `connectionTimeout 15s`; share assert temp-dir prefix + size guard.
- [x] **Step 4: Verify** — Run: `flutter test test/export/` Expected: PASS.

### Task 6: Tách InspectorSession God Object

**Files:**
- Create: `packages/interceptly/lib/src/session/capture_pipeline.dart`, `pending_tracker.dart`, `realtime_store.dart`, `detail_loader.dart`
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart:37-845`
- Modify: `packages/interceptly/lib/interceptly.dart:4-23`
- Test: existing `test/session/*` + `test/e2e/e2e_features_test.dart` làm regression

**Interfaces:**
- Consumes: Tasks 1-3 session behavior (đã khóa bằng test).
- Produces: `InspectorSession` facade <250 dòng; internals `@internal`, barrel chỉ export View/Settings/Summary/Record.

- [x] **Step 1: Write characterization tests** khóa behavior hiện tại (record→entry→loadDetail→clear→dispose) nếu thiếu.
- [x] **Step 2: Run baseline** — Run: `flutter test test/session/ test/e2e/` Expected: PASS trước refactor.
- [x] **Step 3: Implement** tách 4 class, `InspectorSession` compose, đổi `loadDetail(RequestSummary)` thành `loadDetailById(String)` (giữ alias deprecated 1 version), thu hẹp barrel exports.
- [x] **Step 4: Verify** — Run: `flutter analyze && flutter test test/session/ test/e2e/` Expected: PASS, không đổi behavior.

### Task 7: Perf — coalesce notify + JSON isolate + realtime lazy + grouped virtualization

**Files:**
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart:233-239,469-479`
- Modify: `packages/interceptly/lib/src/ui/widgets/json_viewer/json_viewer.dart:184-329`, `json_line_flattener.dart`, `json_search.dart`
- Modify: `packages/interceptly/lib/src/ui/detail/realtime_messages_tab.dart:62-170,420`
- Modify: `packages/interceptly/lib/src/ui/tabs/network_tab.dart:161-358`
- Modify: `packages/interceptly/lib/src/session/master_search_controller.dart:234-250`
- Test: `packages/interceptly/test/stress/notify_coalesce_test.dart` (new, fake_async), extend json stress

**Interfaces:**
- Consumes: Task 6 facade (entries version API).
- Produces: `entriesVersion` + coalesced notify budget; single-pass JSON flatten API.

- [x] **Step 1: Write failing perf tests** — burst 1000 record fake_async assert notify <=~10; JSON 5k lines `_ensureLines` <100ms profile-note (assert invariant + log timing, không hard budget flaky); realtime search debounce.
- [x] **Step 2: Run to verify fail** — Expected: FAIL notify count ~1000.
- [x] **Step 3: Implement** coalesce capture notify 50-100ms (Timer/scheduleFrame); gộp count+match+flatten 1 pass + `compute` khi >5000 lines; realtime memoize parsedJson theo id + debounce 150-200ms + trả view thay vì copy; grouped list flatten thành single ListView/sliver + cache displayUrl + `ValueKey(id)`; search Phase 3 inline khi nhỏ, tăng batch.
- [x] **Step 4: Verify** — Run: `flutter test test/stress/ test/session/realtime_session_test.dart` Expected: PASS; đo DevTools Build time thủ công ghi vào plan.

### Task 8: UI lifecycle + theme + a11y

**Files:**
- Modify: `packages/interceptly/lib/src/ui/overlay/floating_overlay_manager.dart:31-291`
- Modify: `packages/interceptly/lib/src/ui/screens/interceptly_screen.dart:66-69`
- Modify: `packages/interceptly/lib/src/ui/interceptly_theme.dart:9-30,399-406`
- Modify: `filter_panel.dart, settings_bottom_sheet.dart, request_log_item.dart, json_viewer_style.dart, draggable_fab.dart`
- Test: `packages/interceptly/test/ui/overlay/overlay_lifecycle_test.dart` (new)

**Interfaces:**
- Consumes: Task 7 rebuild budgets.
- Produces: Observer-safe overlay; per-subtree theme; accessible controls.

- [x] **Step 1: Write failing tests** — double attach không nhân observer; detach remove observer; slider drag không notify mỗi tick (mock session đếm calls).
- [x] **Step 2: Run to verify fail** — Expected: FAIL.
- [x] **Step 3: Implement** track `_navObserverAttached` + remove trong detach + debounce bringToTop post-frame + `markNeedsBuild` khi config đổi; tách listener header/list (không wrap Scaffold); detail lookup `byId` O(1); slider `onChanged` local + `onChangeEnd` commit; bỏ global brightness (Inherited/param), `JsonViewerColors.of(brightness)`, mono chỉ cho code, lineHeight theo textScaler; thay GestureDetector bằng Switch/FilterChip/Semantics + hit-target 48px; fix search caret + IndexedStack lazy + export batch 10.
- [x] **Step 4: Verify** — Run: `flutter test test/ui/` Expected: PASS.

### Task 9: Code quality dedup + lint siết + release guard

**Files:**
- Create: `packages/interceptly/lib/src/capture/body_bytes.dart`, `packages/interceptly/lib/src/ui/format.dart`
- Modify: adapters `_toBytes/_mapHeaders`, `detail_search.dart:35-41,146-512`, exporters `_mapHeaders`, `interceptly_controller.dart:48-66`
- Modify: `analysis_options.yaml` (root + packages)
- Test: unit `body_bytes_test.dart`, `format_test.dart` (new)

**Interfaces:**
- Consumes: Tasks 4-5 helpers.
- Produces: Single-source `encodeBodyBytes/formatBytes/headerEntries`; `allowInRelease:false` guard.

- [x] **Step 1: Write failing tests** cho `encodeBodyBytes` (String/Map/List/FormData/Stream placeholder), `formatBytes` precision thống nhất.
- [x] **Step 2: Run to verify fail** — Expected: FAIL (chưa có file).
- [x] **Step 3: Implement** shared helpers, thay 3 adapters + 3 format call-sites; gộp `computeMatches` sync/isolate qua `countOccurrences` chung; thu hẹp `dynamic`→`Object?`/`Future<void>`; route export/parse catch qua guard/debugPrint; đặt tên hằng cho magic numbers; thêm `///`; xóa `library <name>;` barrel adapters; bật `public_member_api_docs` cho model/session/export; thêm `assert(!kReleaseMode || allowInRelease)` + docs release checklist.
- [x] **Step 4: Verify** — Run: `dart analyze` 5 packages Expected: No issues.

### Task 10: Testing robustness + DX/docs close-out

**Files:**
- Create: `dio_onerror`, `export_roundtrip`, `isolate_kill`, `bodyStore_eof`, `exporters_golden` tests; per-adapter `README.md`
- Modify: `melos.yaml:5-11`, `interceptly.dart:1`, `pubspec.yaml:2`, `interceptly_settings.dart` dartdoc, `example/`
- Test: toàn bộ suite

**Interfaces:**
- Consumes: mọi tasks trên.
- Produces: Green suite + coverage gate + docs không drift.

- [x] **Step 1: Write missing tests** — Dio error matrix, HAR/Postman write→read byte-identical + schema check, session-pack dispose→reload, isolate-kill fallback + droppedCount, `recordPending` + fake_async 45s timeout, Dio CancelToken, large-file vượt cap `hasDataLoss`, golden exporters + fix `maxEntries=0` false-positive thành `throwsA`.
- [x] **Step 2: Stabilize** — thay polling sleep bằng `expectLater(emitsThrough)`/backoff helper, tag `perf` tách khỏi unit, thêm `melos run test:core/test:stress/coverage --fail-under 80`.
- [x] **Step 3: Docs** — publish WS hoặc sửa 2 README thành path snippet; đồng bộ `maxFramesPerSession` 1000; fix realtime snippet imports; thêm adapter README + Entry-point table + Triggers section (`fabChild/customTrigger/navigatorObserver`); sửa barrel doc + root example pointer + `flutter pub add` không hardcode version + `shouldCapture` limits note.
- [x] **Step 4: Verify** — Run: `melos run analyze && melos run test` Expected: PASS toàn monorepo.

## Self-Review

- Spec coverage: 10 domains đều có task (security T1+T5, session T2+T3, adapters T4, export T5, arch T6, perf T7, UI T8, quality T9, testing/DX T10). Đủ.
- Step scan: mỗi step 1 hành động check được, không transcript body.
- Type consistency: `sanitizeUrl` (T1) dùng lại ở T5; generation fence (T2) dùng ở T3; facade (T6) expose `entriesVersion/byId/loadDetailById` dùng ở T7+T8; helpers (T9) dùng ở T4+T5.
- Review Focus: 6 dòng đều có test pin ở T1/T2/T4/T5.
- Proportion: plan ngắn hơn nhiều so với tổng 10 báo cáo, chỉ quyết định files/signatures/tests.
