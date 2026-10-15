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
