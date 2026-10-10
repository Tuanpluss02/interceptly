part of 'interceptly_controller.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

final _state = _AttachState();

class _AttachState {
  GlobalKey<NavigatorState>? navigatorKey;
  InspectorSession? session;
  InterceptlyConfig? config;
  OverlayEntry? fabEntry;
  StreamSubscription<void>? customTriggerSub;
  bool inspectorIsOpen = false;

  void reset() {
    fabEntry?.remove();
    fabEntry = null;
    customTriggerSub?.cancel();
    customTriggerSub = null;
    navigatorKey = null;
    session = null;
    config = null;
  }
}

// ---------------------------------------------------------------------------
// Public entry points (called from Interceptly class)
// ---------------------------------------------------------------------------

Future<void> _attach({
  required GlobalKey<NavigatorState> navigatorKey,
  InspectorSession? session,
  InterceptlyConfig? config,
  Stream<void>? customTrigger,
}) async {
  _state.reset();

  _state.navigatorKey = navigatorKey;
  _state.session = session ?? InspectorSession.instance;
  _state.config = config ?? const InterceptlyConfig();

  ToastNotification.setNavigatorKey(navigatorKey);
  await _state.session!.initialize();

  if (customTrigger != null) {
    _state.customTriggerSub = customTrigger.listen((_) => _openInspector());
  }

  WidgetsBinding.instance.addPostFrameCallback((_) => _tryInsertOverlays());
}

void _detach() => _state.reset();

// ---------------------------------------------------------------------------
// Inspector navigation
// ---------------------------------------------------------------------------

void _openInspector() {
  _pushInspector(
    session: _state.session ?? InspectorSession.instance,
    nav: _state.navigatorKey?.currentState,
  );
}

void _pushInspector({
  required InspectorSessionView session,
  NavigatorState? nav,
  BuildContext? context,
}) {
  if (_state.inspectorIsOpen) return;

  final navigator = nav ??
      (context != null
          ? Navigator.maybeOf(context, rootNavigator: true)
          : null);
  if (navigator == null) return;

  _state.inspectorIsOpen = true;
  navigator
      .push<void>(
        MaterialPageRoute<void>(
          builder: (_) => InterceptlyScreen(session: session),
        ),
      )
      .whenComplete(() => _state.inspectorIsOpen = false);
}

// ---------------------------------------------------------------------------
// Overlay insertion
// ---------------------------------------------------------------------------

void _tryInsertOverlays([int attempt = 0]) {
  final overlay = _state.navigatorKey?.currentState?.overlay;
  if (overlay == null) {
    if (attempt < 50) {
      Future.delayed(
        const Duration(milliseconds: 100),
        () => _tryInsertOverlays(attempt + 1),
      );
    }
    return;
  }

  final showFab = _state.config?.showFloatingButton ?? true;
  if (showFab && _state.fabEntry == null) {
    _insertFab(overlay);
  }
}

void _insertFab(OverlayState overlay) {
  final config = _state.config ?? const InterceptlyConfig();
  _state.fabEntry = OverlayEntry(
    builder: (context) {
      final fabChild = config.fabChild ??
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
            initPosition: Offset(mq.size.width, mq.size.height / 2),
            securityBottom: mq.padding.bottom,
            securityTop: mq.padding.top,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Material(
                color: InterceptlyGlobalColor.red500,
                elevation: 2,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _openInspector,
                  customBorder: const CircleBorder(),
                  child: Center(child: fabChild),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  overlay.insert(_state.fabEntry!);
}
