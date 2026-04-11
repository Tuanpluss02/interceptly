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
  OverlayEntry? longPressEntry;
  StreamSubscription<UserAccelerometerEvent>? shakeSub;
  StreamSubscription<void>? customTriggerSub;
  DateTime lastShake = DateTime.fromMillisecondsSinceEpoch(0);
  bool inspectorIsOpen = false;

  void reset() {
    fabEntry?.remove();
    fabEntry = null;
    longPressEntry?.remove();
    longPressEntry = null;
    shakeSub?.cancel();
    shakeSub = null;
    customTriggerSub?.cancel();
    customTriggerSub = null;
    navigatorKey = null;
    session = null;
    config = null;
    lastShake = DateTime.fromMillisecondsSinceEpoch(0);
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

  final triggers = _state.config!.triggers;

  if (triggers.contains(InspectorTrigger.shake)) {
    _startShakeListener();
  }

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
    if (attempt < 10) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _tryInsertOverlays(attempt + 1),
      );
    }
    return;
  }

  final triggers = _state.config?.triggers ?? {};
  if (triggers.contains(InspectorTrigger.floatingButton) &&
      _state.fabEntry == null) {
    _insertFab(overlay);
  }
  if (triggers.contains(InspectorTrigger.longPress) &&
      _state.longPressEntry == null) {
    _insertLongPressOverlay(overlay);
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

void _insertLongPressOverlay(OverlayState overlay) {
  final config = _state.config ?? const InterceptlyConfig();
  _state.longPressEntry = OverlayEntry(
    builder: (context) => Positioned.fill(
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(
              duration: config.longPressDuration,
            ),
            (instance) => instance.onLongPress = _openInspector,
          ),
        },
        child: const SizedBox.expand(),
      ),
    ),
  );
  overlay.insert(_state.longPressEntry!);
}

// ---------------------------------------------------------------------------
// Shake detection
// ---------------------------------------------------------------------------

void _startShakeListener() {
  final config = _state.config ?? const InterceptlyConfig();
  try {
    _state.shakeSub = userAccelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen((event) {
      final magnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      if (magnitude < config.shakeThreshold) return;
      final now = DateTime.now();
      if (now.difference(_state.lastShake) < config.shakeMinInterval) {
        return;
      }
      _state.lastShake = now;
      _openInspector();
    }, onError: (_) {});
  } catch (_) {}
}
