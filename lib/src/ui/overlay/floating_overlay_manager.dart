import 'package:flutter/material.dart';

import '../interceptly_theme.dart';
import 'draggable_fab.dart';

class _FloatingOverlayNavigatorObserver extends NavigatorObserver {
  _FloatingOverlayNavigatorObserver(this._manager);

  final FloatingOverlayManager _manager;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _scheduleBringToTop();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _scheduleBringToTop();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _scheduleBringToTop();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _scheduleBringToTop();
  }

  void _scheduleBringToTop() {
    if (_manager.isAttached &&
        !_manager._inspectorIsOpen &&
        _manager._showFloatingButton) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _manager.bringToTop();
      });
    }
  }
}

class _FloatingOverlayLifecycleObserver with WidgetsBindingObserver {
  _FloatingOverlayLifecycleObserver(this._manager);

  final FloatingOverlayManager _manager;

  @override
  void didChangeMetrics() {
    if (_manager.isAttached) {
      _manager.bringToTop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _manager.isAttached) {
      _manager.bringToTop();
    }
  }
}

/// Dedicated manager for Interceptly floating overlay entry and its lifecycle.
class FloatingOverlayManager {
  FloatingOverlayManager._();

  static FloatingOverlayManager? _instance;

  static FloatingOverlayManager get instance =>
      _instance ??= FloatingOverlayManager._();

  GlobalKey<NavigatorState>? _navigatorKey;
  final ValueNotifier<Offset?> persistentPosition =
      ValueNotifier<Offset?>(null);
  OverlayEntry? _fabEntry;
  bool _showFloatingButton = true;
  Widget? _fabChild;
  VoidCallback? _onFabTap;
  bool _inspectorIsOpen = false;
  bool _isAttached = false;
  bool _observerRegistered = false;

  late final _FloatingOverlayNavigatorObserver _navigatorObserver =
      _FloatingOverlayNavigatorObserver(this);
  late final _FloatingOverlayLifecycleObserver _lifecycleObserver =
      _FloatingOverlayLifecycleObserver(this);

  bool get isAttached => _isAttached;
  NavigatorObserver get navigatorObserver => _navigatorObserver;

  void attach({
    required GlobalKey<NavigatorState> navigatorKey,
    bool showFloatingButton = true,
    Widget? fabChild,
    VoidCallback? onFabTap,
  }) {
    if (_isAttached) {
      detach();
    }

    _navigatorKey = navigatorKey;
    _showFloatingButton = showFloatingButton;
    _fabChild = fabChild;
    _onFabTap = onFabTap;
    _isAttached = true;

    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(_lifecycleObserver);
      _observerRegistered = true;
    }

    if (_showFloatingButton) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isAttached) return;
        _tryInsertOverlays();
      });
    }
  }

  void _tryInsertOverlays() {
    if (!_isAttached || !_showFloatingButton) return;

    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null || !overlay.mounted) {
      // Frame-based retry: wait for next post-frame without arbitrary timers.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isAttached || !_showFloatingButton) return;
        final nextOverlay = _navigatorKey?.currentState?.overlay;
        if (nextOverlay != null && nextOverlay.mounted) {
          _tryInsertOverlays();
        } else {
          WidgetsBinding.instance.scheduleFrameCallback((_) {
            if (!_isAttached || !_showFloatingButton) return;
            _tryInsertOverlays();
          });
        }
      });
      return;
    }

    _tryAttachNavigatorObserver();

    if (_fabEntry != null && !_fabEntry!.mounted) {
      _fabEntry = null;
    }

    if (_fabEntry == null) {
      _insertFab(overlay);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        bringToTop();
      });
    } else {
      bringToTop();
    }
  }

  void bringToTop() {
    if (!_isAttached || _inspectorIsOpen || !_showFloatingButton) return;

    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null || !overlay.mounted) return;

    final entry = _fabEntry;
    if (entry == null || !entry.mounted) {
      _insertFab(overlay);
      return;
    }

    try {
      entry.remove();
      overlay.insert(entry);
    } catch (_) {
      _fabEntry = null;
      _insertFab(overlay);
    }
  }

  void _insertFab(OverlayState overlay) {
    if (!overlay.mounted) return;

    _fabEntry = OverlayEntry(
      builder: (context) {
        final fabChild = _fabChild ??
            const Icon(
              Icons.bug_report,
              size: 20,
              color: InterceptlyGlobalColor.white,
            );
        final mq = MediaQuery.of(context);
        return Positioned.fill(
          child: IgnorePointer(
            ignoring: false,
            child: DraggableFab(
              positionNotifier: persistentPosition,
              initPosition: Offset(mq.size.width, mq.size.height / 2),
              securityBottom: mq.padding.bottom,
              securityTop: mq.padding.top,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Theme(
                  data: InterceptlyTheme.themeData(context: context),
                  child: Material(
                    color: InterceptlyGlobalColor.red500,
                    elevation: 2,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _onFabTap,
                      customBorder: const CircleBorder(),
                      child: Center(child: fabChild),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_fabEntry!);
  }

  void _tryAttachNavigatorObserver() {
    final navState = _navigatorKey?.currentState;
    if (navState == null) return;
    try {
      final observers = navState.widget.observers;
      if (!observers.contains(_navigatorObserver)) {
        observers.add(_navigatorObserver);
      }
    } catch (_) {
      // Observers list may be unmodifiable (e.g. const <NavigatorObserver>[])
    }
  }

  void onInspectorOpened() {
    _inspectorIsOpen = true;
  }

  void onInspectorClosed() {
    _inspectorIsOpen = false;
    bringToTop();
  }

  void detach() {
    if (_observerRegistered) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver);
      _observerRegistered = false;
    }

    try {
      _fabEntry?.remove();
    } catch (_) {}

    _fabEntry = null;
    _navigatorKey = null;
    _onFabTap = null;
    _fabChild = null;
    _inspectorIsOpen = false;
    _isAttached = false;
    persistentPosition.value = null;
  }
}
