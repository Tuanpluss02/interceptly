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
