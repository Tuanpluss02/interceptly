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
    _manager.scheduleBringToTopPostFrame();
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
  bool _hiddenForSession = false;
  bool _navObserverAttached = false;
  bool _bringToTopPostFrameScheduled = false;
  int _attachGeneration = 0;

  late final _FloatingOverlayNavigatorObserver _navigatorObserver =
      _FloatingOverlayNavigatorObserver(this);
  late final _FloatingOverlayLifecycleObserver _lifecycleObserver =
      _FloatingOverlayLifecycleObserver(this);

  bool get isAttached => _isAttached;
  bool get isHiddenForSession => _hiddenForSession;
  bool get showFloatingButton => _showFloatingButton;
  NavigatorObserver get navigatorObserver => _navigatorObserver;

  void _removeFabEntry() {
    final entry = _fabEntry;
    _fabEntry = null;
    if (entry != null) {
      try {
        entry.remove();
      } catch (_) {}
      try {
        entry.dispose();
      } catch (_) {}
    }
  }

  void setHiddenForSession(bool hidden) {
    if (_hiddenForSession == hidden) return;
    _hiddenForSession = hidden;
    if (hidden) {
      _removeFabEntry();
    } else {
      if (_isAttached && !_inspectorIsOpen && _showFloatingButton) {
        _tryInsertOverlays();
      }
    }
  }

  /// Schedules a debounced bring-to-top execution on the next frame callback.
  void scheduleBringToTopPostFrame() {
    if (!_isAttached ||
        _inspectorIsOpen ||
        _hiddenForSession ||
        !_showFloatingButton) {
      return;
    }
    if (_bringToTopPostFrameScheduled) return;
    _bringToTopPostFrameScheduled = true;
    final gen = _attachGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bringToTopPostFrameScheduled = false;
      if (!_isAttached || _attachGeneration != gen) return;
      bringToTop();
    });
  }

  void attach({
    required GlobalKey<NavigatorState> navigatorKey,
    bool showFloatingButton = true,
    Widget? fabChild,
    VoidCallback? onFabTap,
  }) {
    if (_isAttached && _navigatorKey == navigatorKey) {
      final configChanged = _showFloatingButton != showFloatingButton ||
          _fabChild != fabChild ||
          _onFabTap != onFabTap;
      _showFloatingButton = showFloatingButton;
      _fabChild = fabChild;
      _onFabTap = onFabTap;
      if (_hiddenForSession && showFloatingButton) {
        _hiddenForSession = false;
        if (!_inspectorIsOpen) {
          _tryInsertOverlays();
        }
      } else if (_fabEntry == null &&
          showFloatingButton &&
          !_hiddenForSession) {
        _tryInsertOverlays();
      } else if (configChanged) {
        _fabEntry?.markNeedsBuild();
      }
      if (!_showFloatingButton) {
        setHiddenForSession(true);
      }
      return;
    }

    if (_isAttached) {
      detach();
    }

    final gen = ++_attachGeneration;
    _navigatorKey = navigatorKey;
    _showFloatingButton = showFloatingButton;
    _fabChild = fabChild;
    _onFabTap = onFabTap;
    _isAttached = true;
    _hiddenForSession = false;

    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(_lifecycleObserver);
      _observerRegistered = true;
    }

    if (_showFloatingButton) {
      final overlay = _navigatorKey?.currentState?.overlay;
      if (overlay != null && overlay.mounted) {
        _tryInsertOverlays();
      } else {
        WidgetsBinding.instance.ensureVisualUpdate();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isAttached || _attachGeneration != gen) return;
          _tryInsertOverlays();
        });
      }
    }
  }

  void _tryInsertOverlays() {
    if (!_isAttached || !_showFloatingButton || _hiddenForSession) return;
    if (_fabEntry != null) return;

    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null || !overlay.mounted) {
      final gen = _attachGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isAttached || _attachGeneration != gen || !_showFloatingButton) {
          return;
        }
        final nextOverlay = _navigatorKey?.currentState?.overlay;
        if (nextOverlay != null && nextOverlay.mounted) {
          _tryInsertOverlays();
        } else {
          WidgetsBinding.instance.scheduleFrameCallback((_) {
            if (!_isAttached ||
                _attachGeneration != gen ||
                !_showFloatingButton) {
              return;
            }
            _tryInsertOverlays();
          });
        }
      });
      return;
    }

    _tryAttachNavigatorObserver();
    _insertFab(overlay);
  }

  void bringToTop() {
    if (!_isAttached ||
        _inspectorIsOpen ||
        !_showFloatingButton ||
        _hiddenForSession) {
      return;
    }

    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null || !overlay.mounted) return;

    final entry = _fabEntry;
    if (entry == null) {
      _insertFab(overlay);
      return;
    }

    if (!entry.mounted) {
      return;
    }

    try {
      entry.remove();
      overlay.insert(entry);
    } catch (_) {
      _removeFabEntry();
      _insertFab(overlay);
    }
  }

  void _insertFab(OverlayState overlay) {
    if (!overlay.mounted || _fabEntry != null) return;

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
                width: 48,
                height: 48,
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
                      child: Semantics(
                        button: true,
                        label: 'Open Interceptly inspector',
                        child: Center(child: fabChild),
                      ),
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
    if (_navObserverAttached) return;
    final navState = _navigatorKey?.currentState;
    if (navState == null) return;
    try {
      final observers = navState.widget.observers;
      if (!observers.contains(_navigatorObserver)) {
        observers.add(_navigatorObserver);
      }
      _navObserverAttached = true;
    } catch (_) {}
  }

  void _detachNavigatorObserver() {
    if (_navObserverAttached) {
      try {
        final navState = _navigatorKey?.currentState;
        navState?.widget.observers.remove(_navigatorObserver);
      } catch (_) {}
      _navObserverAttached = false;
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
    _attachGeneration++;
    if (_observerRegistered) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver);
      _observerRegistered = false;
    }

    _detachNavigatorObserver();

    _removeFabEntry();

    _navigatorKey = null;
    _onFabTap = null;
    _fabChild = null;
    _inspectorIsOpen = false;
    _isAttached = false;
    _hiddenForSession = false;
    _bringToTopPostFrameScheduled = false;
    persistentPosition.value = null;
  }
}
