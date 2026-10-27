## Unreleased

### Fixed
- Preserve capture generation across `HttpRequestContext.copyWith` so amended scopes stay fenced after `clear()`.
- Generation-fenced `clear`/`clearRest`/`clearRealtime` with per-scope futures; `clear-wins` linearization documented.
- Writer restart aliasing via `_StopAck` handshake with `preserveExisting` resume and rotation-count propagation.
- `getRequestDetail` reads beyond UI preview via full decode and propagates `hasDataLoss` to `isTruncated`; `totalChars` now measures full bodies (previously measured UI-preview truncation).
- Rotation sync for detail loader and search; active realtime notifier retention; bound restart queue.

## 2.3.0

### Added
- Dart VM Service Protocol Extensions (`ext.interceptly.*`) registered via `dart:developer` for Model Context Protocol (MCP) server integration:
  - `ext.interceptly.ping`: Connection diagnostics, protocol contract version, and traffic counters.
  - `ext.interceptly.listRequests`: Cursor-paginated HTTP requests with status filtering, multi-phase search, and body inspection.
  - `ext.interceptly.getRequestDetail`: Segmented payload inspection with byte/character truncation.
  - `ext.interceptly.listRealtimeFrames`: Realtime frames by session ID, direction, and frame type.
  - `ext.interceptly.getRealtimeFrameDetail`: Realtime message payload inspection with base64 binary support.
  - `ext.interceptly.getTrafficSummary`: Snapshot metrics (status codes, latency percentiles p50/p90/p95/p99, bandwidth, active realtime sessions).
  - `ext.interceptly.exportCurl`: Replayable cURL generation for recorded requests.
  - `ext.interceptly.setNetworkSimulation`: Remote latency, error rate, and offline condition configuration.
  - `ext.interceptly.clearTraffic`: Remote traffic buffer clearing.
- Multi-phase `SearchService`: Unified search orchestrator combining fast structured metadata filtering with lazy background-decoded body search.
- Documentation for AI coding assistants via Model Context Protocol (`interceptly_mcp`) and `interceptly_socket_io`.

### Changed
- Standardized internal session references to `Interceptly` facade and `InterceptlyEngine`.

## 2.2.0

### Added
- `HttpTrafficCollector.shouldCapture(Uri? uri)` for early URL filtering in HTTP adapters.
- `responseTruncatedAtStorage` parameter in `HttpTrafficCollector.completeResponse` and `failRequest`.
- `HttpCaptureScope.startedAt` timestamp exposure.
- Storage truncation loss detection and separate UI log tabs for REST and Realtime traffic.

## 2.1.1

 - **REFACTOR**: remove redundant message composer title from header in realtime message composer sheet. ([397b5792](https://github.com/Tuanpluss02/interceptly/commit/397b5792c30f933775575b38c7fe3cc380e5d726))

## 2.1.0

### Added
- Realtime inspection engine: `RealtimeFrame` model, `DynamicCircularBuffer` per-session ring buffer with global budget, 100ms throttled UI batching.
- Hybrid realtime storage: `RealtimeBodyStore` append-only temp file with FIFO write queue, 32KB offload threshold, rotation fencing and lazy payload load.
- Bidirectional messaging: `RealtimeTrafficCollector`, `RealtimeSessionScope`, `RealtimeConnectionSender` and `RealtimeMessageDraft` with protocol support for WebSocket, Socket.IO and SSE.
- Realtime UI: `RealtimeDetailPage` with Messages/Overview tabs, live `RealtimeMessagesTab`, chat bar, message composer, resend/edit actions, frame counts and status badges.
- Adapter SPI: unified `HttpTrafficCollector` and `RealtimeTrafficCollector` contracts, satellite adapters migrated to collectors.
- Filtering: protocol filter (REST/Realtime/All), quick filter bar, master search composition with `onlyErrors` option.

### Fixed
- `PendingTracker` no longer times out persistent realtime connections.
- Realtime FAB overlay duplicate entries on startup race eliminated.
- Realtime payload view async race on recycled views guarded.

### Changed
- Realtime hot-path optimized: single-pass frame normalization, zero-copy binary handling, coalesced frame-count notifiers, O(1) budget eviction.
- Dio response handling decoupled from body serialization.

## 2.0.3

### Fixed
- Fixed text selection auto-scrolling horizontally in `JsonViewer` when dragging selection beyond screen edges on long JSON lines.
- Fixed an infinite loop hang in `JsonViewer.countMatches` and `JsonSearch.countIn` when searching with an empty query.

### Changed
- Internal architecture refactoring for `JsonViewer`: split monolithic widget (~1484 lines) into modular components (`json_line`, `json_search`, `json_line_flattener`, `json_scroll_coordinator`, `json_selection_delegate`, `json_gutter`, `json_line_view`) for improved maintainability without changing public APIs.
