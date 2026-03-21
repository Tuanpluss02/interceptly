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
