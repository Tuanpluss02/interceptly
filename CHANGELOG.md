## 2.0.3

### Fixed
- Fixed text selection auto-scrolling horizontally in `JsonViewer` when dragging selection beyond screen edges on long JSON lines.
- Fixed an infinite loop hang in `JsonViewer.countMatches` and `JsonSearch.countIn` when searching with an empty query.

### Changed
- Internal architecture refactoring for `JsonViewer`: split monolithic widget (~1484 lines) into modular components (`json_line`, `json_search`, `json_line_flattener`, `json_scroll_coordinator`, `json_selection_delegate`, `json_gutter`, `json_line_view`) for improved maintainability without changing public APIs.

## 2.0.2

### Fixed
- Fixed a Flutter assertion crash (`assert(!_selectionStartsInScrollable)`) when long-pressing empty spaces inside `JsonViewer`.
- Fixed long lines (such as `Authorization: Bearer <token>`) in `JsonViewer` wrapping or getting visually truncated on narrow screens by disabling soft wrap and improving horizontal scroll boundaries.

## 2.0.1

### Fixed
- Fixed an issue where navigating search matches (Next / Previous match or tab switch) only switched the active tab without scrolling to the matched position in `RequestDetailPage` and `JsonViewer`.
- Fixed match scroll position desynchronization when scrolling away from a match and returning via match navigation.
- Removed deprecated `cacheExtent` usage in `JsonViewer` to avoid analyzer warnings on Flutter 3.47+ / pana score.

### Changed
- `InterceptlySettings.redactedHeaders` now defaults to empty (`const {}`) so headers are captured raw by default unless explicitly configured.

### Added
- Tap the search match counter capsule (`X / Y`) to directly jump/scroll to the currently active match.

## 2.0.0

### Breaking
- `Interceptly.attach()` renamed to `Interceptly.init()` with flattened params; removed `InterceptlyConfig`, `InspectorTrigger`, and shake / long-press triggers (`sensors_plus` dropped).
- `lib/interceptly.dart` now uses `show`-only exports; `InspectorPreferences`, `interceptly_theme`, `IndexEntry`, `BodyLocation` are no longer part of the public barrel.
- `share_plus` replaced by a built-in native share plugin (`android/`, `ios/`); file sharing is mobile-only and returns `false` elsewhere.
- `InterceptlySettings.maxBodyBytes` default raised from 2 MB to 5 MB.

### Added
- `InterceptlySettings.redactedHeaders` (defaults to `authorization`, `cookie`, `set-cookie`, `x-api-key`, case-insensitive) and `shouldCapture(url)` URL predicate.
- `InterceptlySettings.maxUiPreviewBytes` (2 MB) and `pendingTimeout` (45 s) with pending-request rows marked as timed out.
- Per-session temp file isolation via `sessionId`; graceful in-memory fallback when storage or isolates fail.
- Capture guards (`CaptureGuard`) so inspector errors never break host requests.
- Safe UTF-8 truncation, binary sniffing, binary body-pack format, and wider binary content-type detection.
- `FloatingOverlayManager` with `hideFloatingButtonForSession()` / `showFloatingButtonForSession()` and search match navigation in detail pages and JSON viewer.

### Migration
- Replace `Interceptly.attach(navigatorKey: k, config: InterceptlyConfig(triggers: {...}))` with `Interceptly.init(navigatorKey: k, showFloatingButton: ..., settings: const InterceptlySettings(...))`.
- Replace `InspectorTrigger.shake` / `longPress` with `customTrigger` stream or the floating button.
- Import removed barrel types (`InspectorPreferences`, `IndexEntry`, `BodyLocation`, theme) from their `src/` paths instead.

## 1.1.4

### Fixed
- Fixed an issue where `RequestDetailPage` and `CustomRequestPage` inherited the host application's `ThemeData` (e.g. `TabBarTheme`), causing inconsistent layout sizes.
- Improved the reliability of the inspector overlay initialization on app startup by switching from frame-dependent retries to time-based retries, ensuring the trigger icon appears reliably even if `runApp` is delayed by async tasks.

## 1.1.3

### Added
- `InterceptlyAttach.attach()` — one-call setup that registers a `NavigatorObserver` and optionally enables shake-to-open, replacing manual overlay wiring.
- Response size is now displayed in the request list rows and in the detail Overview tab.

### Changed
- Enhanced search text highlighting across JSON viewer and all detail tabs.
- Redesigned request list item with improved layout, clearer spacing, and better dark/light contrast.
- `InspectorSessionView` is now a proper abstract interface — downstream dependencies can depend on the interface rather than the concrete `InspectorSession`.
- `InspectorPreferences` is now a `ChangeNotifier`; the session forwards its change notifications so the UI rebuilds reactively on any preference update.
- Removed raw byte fields (`requestBodyBytesPreview`, `responseBodyBytesPreview`) from the public `RequestRecord` model — body content is exposed as decoded UTF-8 text only.
- Private UI widgets extracted from `network_tab.dart` into a separate part file for better readability.
- Body writes to disk now call `flush()` after each append for improved durability.
- Silent error catch blocks in master search replaced with debug-only logging (`kDebugMode`).

## 1.1.2

### Added
- Postman export functionality for request records and NetworkTab integration
- Request replay and share functionality for request details (cURL, HAR, Postman)
- Method filtering and reset support in the filter panel
- error_summary widget to summarize request errors

### Changed
- Updated RequestDetailPage to use new ReplayHandler and ShareHandler
- Added securityTop parameter to DraggableFab for improved positioning
- Refactored inspector session imports and usage across multiple files
- Updated tests to reflect changes in filtering logic and request handling

## 1.1.1

### Fixed
- Search text being cleared when navigating away and returning to the network tab while search results persisted.

## 1.1.0

### Added
- Advanced filtering by HTTP methods, status codes, and domains.
- Domain grouping to organize network logs.

### Changed
- Improved styling of the filter panel to match the application theme.
- Improved custom request page form to maintain focus state.
- Improved custom request action buttons styling.

### Fixed
- Custom request parameters and headers not applying when sending modified requests.
- Filter list display mapping issue for domains.

## 1.0.2
- Fix broken image links in README.

## 1.0.1

- Added light/dark theme toggle support for better accessibility and user preference.
- Improved replay request UI with enhanced form layout and better input handling.
- Improved documentation and README structure.
- Updated publisher information.

## 1.0.0

Initial release of Interceptly.

- Added network capture for Dio, package:http, and Chopper.
- Added inspector overlay with floating button, shake, long-press, and custom stream triggers.
- Added request detail UI with tabs for request, response, error, and message views.
- Added replay tools including retry and duplicate-and-edit workflows.
- Added export utilities for HAR and cURL.
- Added runtime network simulation profiles (Offline, Slow 3G, Fast 3G, 4G, Wi-Fi, Custom).
- Added session storage with memory index and large-body offload support.
