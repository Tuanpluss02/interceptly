import 'dart:async';

import 'package:flutter/material.dart';
import '../model/interceptly_settings.dart';
import '../model/network_simulation.dart';
import '../model/raw_capture.dart';
import '../model/request_filter.dart';
import '../model/request_record.dart';
import '../model/request_summary.dart';
import '../session/inspector_preferences.dart';
import '../session/inspector_session.dart';
import '../session/inspector_session_view.dart';
import '../ui/interceptly_theme.dart';
import '../ui/overlay/draggable_fab.dart';
import '../ui/screens/interceptly_screen.dart';
import '../ui/widgets/toast_notification.dart';

/// Thin public facade over [InspectorSession].
class Interceptly extends ChangeNotifier {
  Interceptly({InterceptlySettings? settings, InspectorSession? session})
      : _session = session ?? InspectorSession(settings: settings) {
    _session.addListener(notifyListeners);
  }

  static Interceptly? _sharedInstance;

  static Interceptly get instance {
    return _sharedInstance ??= Interceptly(session: InspectorSession.instance);
  }

  final InspectorSession _session;

  // ---------------------------------------------------------------------------
  // init / detach
  // ---------------------------------------------------------------------------

  /// Configures global settings for Interceptly.
  static void configure(InterceptlySettings settings) {
    InspectorSession.configure(settings);
  }

  /// Single entrypoint to initialize Interceptly: attaches the UI to [navigatorKey]
  /// and applies all desired configuration options in one clean call.
  ///
  /// ```dart
  /// Interceptly.init(
  ///   navigatorKey: _navKey,
  ///   maxBodyBytes: 1024 * 1024,
  ///   redactedHeaders: {'authorization', 'x-api-key'},
  ///   showFloatingButton: true,
  /// );
  /// ```
  static Future<void> init({
    required GlobalKey<NavigatorState> navigatorKey,
    bool showFloatingButton = true,
    Widget? fabChild,
    Stream<void>? customTrigger,
    int? maxBodyBytes,
    int? maxEntries,
    Set<String>? redactedHeaders,
    bool Function(String url)? shouldCapture,
    Duration? pendingTimeout,
    int? bodyOffloadThreshold,
    InterceptlySettings? settings,
    InspectorSession? session,
  }) {
    final baseSettings =
        settings ?? (session?.settings ?? InspectorSession.instance.settings);
    final effectiveSettings = baseSettings.copyWith(
      maxBodyBytes: maxBodyBytes,
      maxEntries: maxEntries,
      redactedHeaders: redactedHeaders,
      shouldCapture: shouldCapture,
      pendingTimeout: pendingTimeout,
      bodyOffloadThreshold: bodyOffloadThreshold,
    );

    final targetSession = session ?? InspectorSession.instance;
    targetSession.configureSession(effectiveSettings);

    return _init(
      navigatorKey: navigatorKey,
      session: targetSession,
      showFloatingButton: showFloatingButton,
      fabChild: fabChild,
      customTrigger: customTrigger,
    );
  }

  /// Removes all overlay entries and cancels all trigger subscriptions.
  static void detach() => _detach();

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  /// Opens the inspector screen.
  ///
  /// Pass a [context] only if [init] has not been called yet.
  static void showInspector([BuildContext? context]) {
    assert(
      _state.navigatorKey != null || context != null,
      'Interceptly.showInspector() requires either a BuildContext or a prior '
      'call to Interceptly.init().',
    );
    _pushInspector(
      session: InspectorSession.instance,
      nav: _state.navigatorKey?.currentState,
      context: context,
    );
  }

  // ---------------------------------------------------------------------------
  // Passthrough getters
  // ---------------------------------------------------------------------------

  InspectorSessionView get session => _session;
  InterceptlySettings get settings => _session.settings;
  InspectorPreferences get preferences => _session.preferences;
  List<RequestSummary> get calls => _session.entries;
  RequestFilter get filter => _session.filter;
  int get droppedEvents => _session.droppedCount;
  bool get isEnabled => _session.isEnabled;
  NetworkSimulationProfile get networkSimulation => _session.networkSimulation;

  // ---------------------------------------------------------------------------
  // Capture control
  // ---------------------------------------------------------------------------

  void enable() => _session.enable();
  void disable() => _session.disable();
  Future<void> initialize() => _session.initialize();
  void recordCapture(RawCapture capture) => _session.record(capture);
  Future<RequestRecord> loadDetail(RequestSummary summary) =>
      _session.loadDetail(summary);
  void applyFilter(RequestFilter filter) => _session.applyFilter(filter);
  void setNetworkSimulation(NetworkSimulationProfile profile) =>
      _session.setNetworkSimulation(profile);
  void clearNetworkSimulation() => _session.clearNetworkSimulation();
  Future<void> clear() => _session.clear();

  @override
  void dispose() {
    _session.removeListener(notifyListeners);
    if (identical(_sharedInstance, this)) {
      _sharedInstance = null;
    }
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// UI State & Overlay Wiring
// ---------------------------------------------------------------------------

final _state = _AttachState();

class _AttachState {
  GlobalKey<NavigatorState>? navigatorKey;
  InspectorSession? session;
  bool showFloatingButton = true;
  Widget? fabChild;
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
    showFloatingButton = true;
    fabChild = null;
  }
}

Future<void> _init({
  required GlobalKey<NavigatorState> navigatorKey,
  InspectorSession? session,
  bool showFloatingButton = true,
  Widget? fabChild,
  Stream<void>? customTrigger,
}) async {
  _state.reset();

  _state.navigatorKey = navigatorKey;
  _state.session = session ?? InspectorSession.instance;
  _state.showFloatingButton = showFloatingButton;
  _state.fabChild = fabChild;

  ToastNotification.setNavigatorKey(navigatorKey);
  await _state.session!.initialize();

  if (customTrigger != null) {
    _state.customTriggerSub = customTrigger.listen((_) => _openInspector());
  }

  WidgetsBinding.instance.addPostFrameCallback((_) => _tryInsertOverlays());
}

void _detach() => _state.reset();

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

  if (_state.showFloatingButton && _state.fabEntry == null) {
    _insertFab(overlay);
  }
}

void _insertFab(OverlayState overlay) {
  _state.fabEntry = OverlayEntry(
    builder: (context) {
      final fabChild = _state.fabChild ??
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
