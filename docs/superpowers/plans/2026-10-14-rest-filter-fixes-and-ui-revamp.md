# REST Filter Fixes and UI Revamp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix critical filtering bugs (search overriding filters, status 0/error leakage, deselect-all paradox, stale session filter state) and redesign the REST filter UI with a modern quick-filter chip bar and an upgraded `FilterPanel` using strictly `InterceptlyTheme` tokens.

**Architecture:** 
- Enhance `RequestFilter` with `onlyErrors` and explicit inclusion logic (distinguishing "all" vs "none" vs "only errors").
- Unify search and filtering in `InspectorSession.entries` so search queries and active filter criteria compose (`search.results.where(filter.matches)`).
- Add a horizontal `QuickFilterBar` in `NetworkTab` beneath search for instant single-tap filtering (`All`, `Errors`, `2xx`, `4xx/5xx`, `POST`, `GET`).
- Revamp `FilterPanel` modal bottom sheet using 100% `InterceptlyTheme` styling, adding domain search, clean method/status chips, and responsive count badge.

**Tech Stack:** Flutter, Dart, `package:interceptly`

**Spec:** In-conversation design approved on 2026-10-14.

## Global Constraints

- Exclusively use `InterceptlyTheme` (`typography`, `colors`, `radius`, `spacing`, `themeData`).
- Absolutely DO NOT inherit or rely on the host application's `Theme.of(context)` properties (prevent theme leakage).
- Backward compatibility: Existing `RequestFilter` constructors and public API methods must continue to work.
- All existing tests (701+) must continue to pass with zero regressions.
- Static analysis (`flutter analyze`) must report 0 issues.

## Review Focus

1. **Search + Filter composition**: When both a search query and a method/status filter are active, entries must satisfy BOTH criteria, never overriding each other.
2. **Deselect All behavior**: When a user unselects all methods or domains in the UI, it must NOT fall back to "match all"; it should either disable the action or display empty results.
3. **Pending / Zero-Status requests**: Requests with `statusCode == 0` (in-flight or connection errors) must respect filters (not leak through when filtering for 2xx).
4. **Theme isolation**: No standard Material widgets with unconstrained default colors; every widget must explicitly bind colors from `InterceptlyTheme`.
5. **Dynamic Filter updates**: If logs or filters are cleared or changed externally, the filter bar and badge must update reactively.

---

### Task 1: Core Logic - Filter Model & Search-Filter Composition

**Files:**
- Modify: `packages/interceptly/lib/src/model/request_filter.dart`
- Modify: `packages/interceptly/lib/src/session/inspector_session.dart:180-195`
- Create: `packages/interceptly/test/session/search_filter_composition_test.dart`
- Modify: `packages/interceptly/test/session/memory_index_filter_test.dart` (or model test)

**Interfaces:**
- Consumes: `RequestSummary`, `IndexEntry`, `RequestFilter`
- Produces: `RequestFilter.onlyErrors`, `RequestFilter.includePending`, composed `InspectorSession.entries`

- [ ] **Step 1: Write failing tests for search-filter composition and error/pending filtering**

```dart
// test/session/search_filter_composition_test.dart
test('entries compose both search query and filter criteria simultaneously', () async {
  final session = InspectorSession();
  session.recordPending(id: '1', method: 'GET', url: 'https://api.com/users', timestamp: DateTime.now());
  session.recordPending(id: '2', method: 'POST', url: 'https://api.com/users', timestamp: DateTime.now());
  session.recordPending(id: '3', method: 'POST', url: 'https://api.com/posts', timestamp: DateTime.now());
  session.recordResponse(id: '1', statusCode: 200, durationMs: 10, responseHeaders: {}, responseBody: '');
  session.recordResponse(id: '2', statusCode: 200, durationMs: 10, responseHeaders: {}, responseBody: '');
  session.recordResponse(id: '3', statusCode: 500, durationMs: 10, responseHeaders: {}, responseBody: '');

  // Apply method filter: POST only
  session.applyFilter(RequestFilter(methods: {'POST'}));
  expect(session.entries.length, equals(2)); // id 2 and 3

  // Now start search: "users"
  await session.startMasterSearch('users');
  // Must return only id 2 (POST + users), NOT id 1 (GET + users) and NOT id 3 (POST + posts)
  expect(session.entries.map((e) => e.id).toList(), equals(['2']));
});

test('onlyErrors filter matches 4xx, 5xx and connection errors', () {
  final filter = RequestFilter(onlyErrors: true);
  final ok = IndexEntry(id: '1', method: 'GET', url: 'https://a.com', statusCode: 200, durationMs: 1, requestSizeBytes: 0, responseSizeBytes: 0, timestamp: DateTime.now(), hasError: false, requestTruncation: const BodyTruncation.complete(0), responseTruncation: const BodyTruncation.complete(0), bodyLocation: BodyLocation.memory);
  final clientErr = ok.copyWith(id: '2', statusCode: 404, hasError: true);
  final serverErr = ok.copyWith(id: '3', statusCode: 500, hasError: true);
  final netErr = ok.copyWith(id: '4', statusCode: 0, hasError: true);
  final pending = ok.copyWith(id: '5', statusCode: 0, hasError: false);

  expect(filter.matches(ok), isFalse);
  expect(filter.matches(clientErr), isTrue);
  expect(filter.matches(serverErr), isTrue);
  expect(filter.matches(netErr), isTrue);
  expect(filter.matches(pending), isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/session/search_filter_composition_test.dart`
Expected: FAIL (search ignores filter / `onlyErrors` not defined)

- [ ] **Step 3: Implement `onlyErrors` and search-filter composition**

In `packages/interceptly/lib/src/model/request_filter.dart`:
- Add `final bool onlyErrors;` (default `false`) and `final bool includePending;` (default `true`).
- In `matches(RequestSummary entry)`:
  - If `onlyErrors` is true: verify `entry.hasError || entry.statusCode >= 400`. If not, return `false`.
  - If `entry.statusCode == 0`: if `entry.hasError` (network failure), treat as error (matches only if 4xx/5xx or `onlyErrors` is allowed); if `!entry.hasError` (pending), only include if `includePending` is true.
  - Update `isEmpty`, `activeFilterCount`, `copyWith`, `==`, and `hashCode`.
In `packages/interceptly/lib/src/session/inspector_session.dart`:
- Update `entries`:
```dart
  @override
  List<RequestSummary> get entries {
    final baseList = _search.isActive
        ? (_search.results ?? const <IndexEntry>[])
        : _memoryIndex.entries;
    if (_filter.isEmpty) {
      return baseList.cast<RequestSummary>();
    }
    return baseList.where(_filter.matches).toList().cast<RequestSummary>();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/session/search_filter_composition_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/model/request_filter.dart packages/interceptly/lib/src/session/inspector_session.dart packages/interceptly/test/session/search_filter_composition_test.dart
git commit -m "feat(core): compose master search with active filter and add onlyErrors option"
```

---

### Task 2: Quick Filter Bar Component

**Files:**
- Create: `packages/interceptly/lib/src/ui/tabs/quick_filter_bar.dart`
- Modify: `packages/interceptly/lib/src/ui/widgets/filter_badge.dart`
- Create: `packages/interceptly/test/ui/tabs/quick_filter_bar_test.dart`

**Interfaces:**
- Consumes: `RequestFilter`, `InspectorSessionView`, `InterceptlyTheme`
- Produces: `QuickFilterBar` widget, `FilterBadge` with active tint

- [ ] **Step 1: Write failing widget test for `QuickFilterBar`**

```dart
// test/ui/tabs/quick_filter_bar_test.dart
testWidgets('renders quick filter chips and toggles onlyErrors filter', (tester) async {
  final session = InspectorSession();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: QuickFilterBar(session: session),
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.text('All'), findsOneWidget);
  expect(find.text('Errors'), findsOneWidget);
  expect(find.text('2xx'), findsOneWidget);

  // Tap "Errors" chip
  await tester.tap(find.text('Errors'));
  await tester.pumpAndSettle();

  expect(session.filter.onlyErrors, isTrue);

  // Tap "All" chip
  await tester.tap(find.text('All'));
  await tester.pumpAndSettle();

  expect(session.filter.onlyErrors, isFalse);
  expect(session.filter.isEmpty, isTrue);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/tabs/quick_filter_bar_test.dart`
Expected: FAIL (`QuickFilterBar` not defined)

- [ ] **Step 3: Implement `QuickFilterBar` and update `FilterBadge`**

In `packages/interceptly/lib/src/ui/tabs/quick_filter_bar.dart`:
- Implement a horizontally scrollable list of chips:
  - `All`: active when `session.filter.isEmpty`.
  - `Errors`: active when `session.filter.onlyErrors`. Styled with `InterceptlyTheme.red500` accent.
  - `2xx`: toggles `include2xx: true`, other ranges false.
  - `4xx/5xx`: toggles `include4xx: true, include5xx: true, include2xx: false, include3xx: false`.
  - `GET`, `POST`: single-tap method filters.
- Use `InterceptlyTheme.colors`, `InterceptlyTheme.typography`, `InterceptlyTheme.radius.full` or `.md`.
- In `FilterBadge`: when `activeFiltersCount > 0`, highlight icon with `InterceptlyTheme.indigo500` background or badge.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/tabs/quick_filter_bar_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/ui/tabs/quick_filter_bar.dart packages/interceptly/lib/src/ui/widgets/filter_badge.dart packages/interceptly/test/ui/tabs/quick_filter_bar_test.dart
git commit -m "feat(ui): add QuickFilterBar component with preset chips"
```

---

### Task 3: Redesign `FilterPanel` Bottom Sheet

**Files:**
- Modify: `packages/interceptly/lib/src/ui/filter/filter_panel.dart`
- Modify: `packages/interceptly/test/ui/filter/filter_panel_test.dart` (or create if missing)

**Interfaces:**
- Consumes: `RequestFilter`, `availableDomains`, `onFilterChanged`, `InterceptlyTheme`
- Produces: Redesigned modal bottom sheet `FilterPanel`

- [ ] **Step 1: Write widget test verifying new `FilterPanel` features**

```dart
// test/ui/filter/filter_panel_test.dart
testWidgets('FilterPanel allows toggling Errors Only, searching domains, and applying filters', (tester) async {
  RequestFilter? applied;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => FilterPanel.show(
            context: ctx,
            currentFilter: RequestFilter(),
            availableDomains: {'api.github.com', 'stormx.dev'},
            onFilterChanged: (f) => applied = f,
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();

  expect(find.text('Filter Requests'), findsOneWidget);
  expect(find.text('Errors Only'), findsOneWidget);

  // Toggle Errors Only
  await tester.tap(find.text('Errors Only'));
  await tester.pumpAndSettle();

  // Tap Apply
  await tester.tap(find.textContaining('Apply'));
  await tester.pumpAndSettle();

  expect(applied?.onlyErrors, isTrue);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/filter/filter_panel_test.dart`
Expected: FAIL

- [ ] **Step 3: Redesign `FilterPanel` layout and logic**

In `packages/interceptly/lib/src/ui/filter/filter_panel.dart`:
- Header:
  - Clean title "Filter Requests", with active count badge `_activeFilterCount`.
  - "Reset All" text button styled with `InterceptlyTheme.colors.actionPrimary`.
- Section 1: **Quick Preset**: "Errors Only" toggle switch / chip.
- Section 2: **HTTP Methods**: Material-style filter chips for `GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `HEAD` using `InterceptlyTheme.getMethodStyle`.
- Section 3: **Status Codes**: 4 styled filter chips (`2xx Success`, `3xx Redirect`, `4xx Client Err`, `5xx Server Err`) with color indicators.
- Section 4: **Domains**:
  - If domains > 4, include a compact search input `InterceptlySearchField`.
  - "Select All" / "Deselect All" action.
  - Domain items with clean check icons and count tags.
- Fix empty-methods bug: if user deselects all methods, either keep at least one selected or set empty list and disable apply with tooltip "Select at least one method".
- Footer:
  - Sticky bottom container with `InterceptlyTheme.dividerSubtle`.
  - Full-width `FilledButton` styled with `InterceptlyTheme.colors.actionPrimary`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/filter/filter_panel_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/ui/filter/filter_panel.dart packages/interceptly/test/ui/filter/filter_panel_test.dart
git commit -m "refactor(ui): revamp FilterPanel with InterceptlyTheme, presets and domain search"
```

---

### Task 4: Integrate QuickFilterBar and FilterBadge into NetworkTab & Screen

**Files:**
- Modify: `packages/interceptly/lib/src/ui/tabs/network_tab.dart`
- Modify: `packages/interceptly/lib/src/ui/tabs/network_tab_widgets.dart`
- Modify: `packages/interceptly/lib/src/ui/screens/interceptly_screen.dart`
- Modify/Create: `packages/interceptly/test/ui/tabs/network_tab_protocol_test.dart`

**Interfaces:**
- Consumes: `QuickFilterBar`, `FilterBadge`, `session.filter`
- Produces: Integrated `NetworkTab` with search, filter badge, and quick chips

- [ ] **Step 1: Write integration test for NetworkTab filter bar**

```dart
testWidgets('NetworkTab shows FilterBadge with count when filter is active', (tester) async {
  final session = InspectorSession();
  session.applyFilter(RequestFilter(onlyErrors: true));

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NetworkTab(session: session),
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.byType(FilterBadge), findsOneWidget);
  expect(find.byType(QuickFilterBar), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/tabs/network_tab_protocol_test.dart`
Expected: FAIL

- [ ] **Step 3: Integrate components**

In `packages/interceptly/lib/src/ui/tabs/network_tab_widgets.dart`:
- Replace raw `IconButton` in `_SearchFilterBar` with `FilterBadge(activeFiltersCount: filterCount, onTap: onShowFilter)`.
In `packages/interceptly/lib/src/ui/tabs/network_tab.dart`:
- Add `QuickFilterBar(session: widget.session)` directly below `_SearchFilterBar` (only for `NetworkProtocol.rest` and `NetworkProtocol.all`).
In `packages/interceptly/lib/src/ui/screens/interceptly_screen.dart`:
- Remove redundant local `late RequestFilter _filter;` state. Always read `widget.session.filter` directly to avoid stale state.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/tabs/network_tab_protocol_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/ui/tabs/network_tab.dart packages/interceptly/lib/src/ui/tabs/network_tab_widgets.dart packages/interceptly/lib/src/ui/screens/interceptly_screen.dart
git commit -m "feat(ui): integrate QuickFilterBar and FilterBadge into NetworkTab and InterceptlyScreen"
```

---

### Task 5: Monorepo Verification & Regression Testing

**Files:**
- All packages & example app

- [ ] **Step 1: Run static analysis on all packages**

```bash
flutter analyze packages/interceptly
flutter analyze packages/interceptly_web_socket
flutter analyze packages/interceptly_dio
flutter analyze packages/interceptly_http
flutter analyze packages/interceptly_chopper
flutter analyze packages/interceptly/example
```
Expected: 0 issues across all packages.

- [ ] **Step 2: Run full test suite**

```bash
cd packages/interceptly && flutter test
cd packages/interceptly_web_socket && flutter test
```
Expected: All tests pass (700+ tests).

- [ ] **Step 3: Commit all remaining changes if any**

```bash
git status
```
Expected: Working tree clean.
