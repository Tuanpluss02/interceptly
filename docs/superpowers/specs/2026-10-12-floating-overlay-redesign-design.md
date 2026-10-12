# Architectural Design: Floating Overlay Manager Redesign

- **Date:** 2026-10-12
- **Topic:** Floating Overlay Manager Architecture Redesign
- **Status:** Proposed

## 1. Context & Problem Statement

In `interceptly`, the floating bug action button (FAB) allows developers to inspect network traffic on-device with zero friction.
However, the previous overlay implementation in [`lib/src/core/interceptly_controller.dart`](file:///Users/tuanpluss02/Documents/Boltx/BDS/bds_thm/packages/interceptly/lib/src/core/interceptly_controller.dart) was fraught with fragile workarounds:
1. **120-Attempt Polling Loop (`Future.delayed`):** Attempted to poll `navigatorKey.currentState?.overlay` up to 120 times across 60 seconds because it lacked reactive frame lifecycle binding.
2. **Occlusion on Route Push / Replace:** When routes changed (such as `SplashPage` calling `pushReplacement` to `HomePage`), Flutter pushed new opaque `ModalRoute` entries above the existing FAB `OverlayEntry`, burying the button.
3. **Position Loss on Re-insert:** Calling `entry.remove()` and `overlay.insert(entry)` unmounted and remounted the `DraggableFab`, discarding its state and snapping the button back to the default position.
4. **Tangled Global State:** Overlay logic was scattered across `_AttachState`, `_InterceptlyLifecycleObserver`, `_InterceptlyNavigatorObserver`, `_tryInsertOverlays`, `_bringFabToTop`, and `_insertFab`.

## 2. Requirements & Constraints

1. **Strict Zero-Config Consumer API:** Consuming apps must only call:
   ```dart
   Interceptly.init(navigatorKey: AppRouter.navigatorKey);
   ```
   No requiring `builder`, no manual `navigatorObservers`, no multi-step setup.
2. **Reliable Visibility:** The FAB must remain visible and interactive across:
   - Cold app start
   - Hot Restart
   - Standard route pushes (`Navigator.push`)
   - Route replacements (`Navigator.pushReplacement`)
   - Declarative route changes (`GoRouter`, `Beamer`, `AutoRoute`)
   - Popping the inspector page back to the app
3. **Drag Position Retention:** If the user drags the bug icon to a custom position, that position must be preserved across route transitions and screen changes.
4. **No Polling:** Completely eliminate `Future.delayed` retry loops; tie attachment directly to Flutter's `WidgetsBinding` frame scheduler.
5. **Clean Architecture:** Encapsulate all overlay lifecycle, position management, and observer binding into a dedicated, self-contained `FloatingOverlayManager`.

---

## 3. Architecture & Components

```
┌────────────────────────────────────────────────────────┐
│             Interceptly Public API Facade             │
│   Interceptly.init(...)  /  Interceptly.detach()       │
└──────────────────────────┬─────────────────────────────┘
                           │ delegates overlay tasks
                           ▼
┌────────────────────────────────────────────────────────┐
│                FloatingOverlayManager                  │
├────────────────────────────────────────────────────────┤
│ - navigatorKey: GlobalKey<NavigatorState>              │
│ - persistentPosition: ValueNotifier<Offset?>           │
│ - fabEntry: OverlayEntry?                              │
│ - observer: _InterceptlyNavigatorObserver              │
│ - lifecycleObserver: _InterceptlyLifecycleObserver     │
├────────────────────────────────────────────────────────┤
│ + attach()                                             │
│ + detach()                                             │
│ + bringToTop()                                         │
│ + onInspectorOpened()                                  │
│ + onInspectorClosed()                                  │
└───────────┬────────────────────────────────────────────┘
            │ builds inside OverlayEntry
            ▼
┌────────────────────────────────────────────────────────┐
│                      DraggableFab                      │
│ - Reads/writes persistentPosition                      │
│ - Snaps to screen edge on gesture end                  │
│ - Does not reset position on element remount           │
└────────────────────────────────────────────────────────┘
```

### 3.1. `FloatingOverlayManager` Responsibilities
Located at `lib/src/ui/overlay/floating_overlay_manager.dart`:
- **Reactive Frame Attachment:** Instead of delayed timers, uses `WidgetsBinding.instance.addPostFrameCallback`. If the Navigator is not yet mounted (e.g. before initial frame), schedules on the next frame callback via `scheduleFrameCallback`.
- **Topmost Z-Index Maintenance (`bringToTop`):**
  - Invoked automatically when routes push, pop, or replace.
  - Safely brings the existing entry to the top of the active overlay (`entry.remove()` + `overlay.insert(entry)`).
  - Detects if `entry` belonged to a disposed `OverlayState` (such as during app restart) and cleanly re-creates the entry on the active overlay.
  - Skips re-ordering if the inspector screen is currently open to avoid obscuring inspector UI.
- **Auto Observer Hook (`_tryAttachNavigatorObserver`):**
  - Checks `navigatorKey.currentState?.widget.observers`. If growable and not present, automatically adds the manager's navigator observer.
- **Position Persistence:**
  - Maintains `_positionNotifier = ValueNotifier<Offset?>(null)`.
  - When `DraggableFab` updates its position, it updates this notifier.
  - When remounted, `DraggableFab` initializes directly from this notifier.

### 3.2. Refactoring `DraggableFab`
- Support an optional `positionNotifier` or initialize from persistent state.
- Keep edge snapping and boundary clamping intact.

### 3.3. Refactoring `Interceptly` Controller
- Remove all ad-hoc overlay code from `lib/src/core/interceptly_controller.dart`.
- `Interceptly.init(...)` delegates overlay management to `FloatingOverlayManager.instance.attach(...)`.
- `Interceptly.detach()` delegates to `FloatingOverlayManager.instance.detach()`.
- Route inspector open/close notifications directly through the manager.

---

## 4. Error Handling & Edge Cases

1. **Overlay unmounted / disposed during app restart:**
   - When `OverlayState` is disposed, `entry.remove()` or `overlay.insert(entry)` could throw if referencing old state. `FloatingOverlayManager` wraps overlay operations with graceful self-healing: if an entry is stale, it marks it null and creates a fresh entry on the active overlay.
2. **NavigatorKey currentState is null on launch:**
   - Frame callback will retry cleanly on the next frame (`scheduleFrameCallback`) with a safe limit of frames without any busy-wait timer loops.
3. **Screen rotation / Window resize:**
   - Handled via `WidgetsBindingObserver.didChangeMetrics`. `bringToTop()` is invoked and `DraggableFab` clamps to the new dimensions without resetting user position.
4. **App background / resume:**
   - Handled via `WidgetsBindingObserver.didChangeAppLifecycleState`. Verifies the overlay entry when the app returns to the foreground.

---

## 5. Verification & Testing Plan

1. **Unit & Widget Tests (`test/floating_button_overlay_test.dart`):**
   - **Test 1:** Initial render on first frame without polling delay.
   - **Test 2:** Pushed page does not occlude FAB; FAB is tappable on top.
   - **Test 3:** Replaced route (`pushReplacement`) maintains FAB on top.
   - **Test 4:** Dragging FAB to custom position, pushing a new page, and verifying FAB position remains unchanged.
   - **Test 5:** Simulating app restart with new `Navigator` cleanly re-attaches FAB.
   - **Test 6:** Opening and popping Inspector cleanly manages overlay visibility.
2. **Full Test Suite & Analysis:**
   - `flutter analyze` with 0 warnings/errors.
   - `flutter test` with all tests passing.
