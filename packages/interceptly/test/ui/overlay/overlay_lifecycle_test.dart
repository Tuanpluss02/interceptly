import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/domain_group.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';
import 'package:interceptly/src/model/network_simulation.dart';
import 'package:interceptly/src/model/realtime_frame.dart';
import 'package:interceptly/src/model/request_filter.dart';
import 'package:interceptly/src/model/request_record.dart';
import 'package:interceptly/src/model/request_summary.dart';
import 'package:interceptly/src/model/search_match_scope.dart';
import 'package:interceptly/src/session/inspector_preferences.dart';
import 'package:interceptly/src/session/inspector_session_view.dart';
import 'package:interceptly/src/ui/overlay/floating_overlay_manager.dart';
import 'package:interceptly/src/ui/settings/settings_bottom_sheet.dart';

class _FakeSessionView extends ChangeNotifier implements InspectorSessionView {
  int setNetworkSimulationCallCount = 0;
  NetworkSimulationProfile _sim = const NetworkSimulationProfile(
    name: 'Custom',
    offline: false,
    latencyMs: 100,
    downloadKbps: 1000,
    uploadKbps: 500,
  );

  final _prefs = InspectorPreferences();

  @override
  NetworkSimulationProfile get networkSimulation => _sim;

  @override
  void setNetworkSimulation(NetworkSimulationProfile profile) {
    setNetworkSimulationCallCount++;
    _sim = profile;
    notifyListeners();
  }

  @override
  void clearNetworkSimulation() {
    _sim = NetworkSimulationProfile.none;
    notifyListeners();
  }

  @override
  InspectorPreferences get preferences => _prefs;

  @override
  InterceptlySettings get settings => const InterceptlySettings();

  @override
  List<RequestSummary> get entries => const [];

  @override
  int get entriesVersion => 0;

  @override
  RequestFilter get filter => RequestFilter();

  @override
  bool get isEnabled => true;

  @override
  int get droppedCount => 0;

  @override
  String? get masterQuery => null;

  @override
  bool get isMasterSearchActive => false;

  @override
  bool get isScanningBodies => false;

  @override
  bool get isScanningFiles => false;

  @override
  bool get groupingEnabled => false;

  @override
  Set<SearchMatchScope> getSearchScopes(String id) => const {};

  @override
  Future<RequestRecord> loadDetail(RequestSummary summary) =>
      throw UnimplementedError();

  @override
  Future<RequestRecord> loadDetailById(String id) =>
      throw UnimplementedError();

  @override
  RequestSummary? byId(String id) => null;

  @override
  void enable() {}

  @override
  void disable() {}

  @override
  Future<void> clear() async {}

  @override
  void applyFilter(RequestFilter filter) {}

  @override
  void clearFilter() {}

  @override
  List<DomainGroup> getGroupedRecords() => const [];

  @override
  void toggleGrouping(bool enabled) {}

  @override
  void toggleDomainExpanded(String domain) {}

  @override
  void cancelMasterSearch() {}

  @override
  Future<void> startMasterSearch(String query) async {}

  @override
  Set<String> get availableDomains => const {};

  @override
  List<RealtimeFrame> getRealtimeFrames(String sessionId) => const [];

}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    FloatingOverlayManager.instance.detach();
  });

  group('FloatingOverlayManager lifecycle', () {
    testWidgets('double attach does not duplicate navigator observer',
        (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      final observers = <NavigatorObserver>[];

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          navigatorObservers: observers,
          home: const Scaffold(body: Text('Home')),
        ),
      );

      FloatingOverlayManager.instance.attach(
        navigatorKey: navKey,
        showFloatingButton: true,
      );
      await tester.pumpAndSettle();

      final obs = FloatingOverlayManager.instance.navigatorObserver;
      final matchCountFirst =
          navKey.currentState!.widget.observers.where((o) => identical(o, obs)).length;
      expect(matchCountFirst, 1);

      FloatingOverlayManager.instance.attach(
        navigatorKey: navKey,
        showFloatingButton: true,
      );
      await tester.pumpAndSettle();

      final matchCountSecond =
          navKey.currentState!.widget.observers.where((o) => identical(o, obs)).length;
      expect(matchCountSecond, 1);
    });

    testWidgets('detach removes navigator observer from navigator',
        (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      final observers = <NavigatorObserver>[];

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          navigatorObservers: observers,
          home: const Scaffold(body: Text('Home')),
        ),
      );

      FloatingOverlayManager.instance.attach(
        navigatorKey: navKey,
        showFloatingButton: true,
      );
      await tester.pumpAndSettle();

      final obs = FloatingOverlayManager.instance.navigatorObserver;
      expect(navKey.currentState!.widget.observers.contains(obs), isTrue);

      FloatingOverlayManager.instance.detach();
      await tester.pumpAndSettle();

      expect(navKey.currentState!.widget.observers.contains(obs), isFalse);
    });
  });

  group('SettingsBottomSheet slider commit behavior', () {
    testWidgets('slider drag updates local state and commits only on onChangeEnd',
        (tester) async {
      final fakeSession = _FakeSessionView();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsBottomSheet(session: fakeSession),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sliderFinder = find.byType(Slider).first;
      expect(sliderFinder, findsOneWidget);

      final slider = tester.widget<Slider>(sliderFinder);
      expect(slider.onChangeEnd, isNotNull);

      slider.onChanged!(250);
      await tester.pump();
      slider.onChanged!(300);
      await tester.pump();

      expect(
        fakeSession.setNetworkSimulationCallCount,
        0,
        reason: 'Should not commit to session during drag ticks (onChanged)',
      );

      slider.onChangeEnd!(300);
      await tester.pumpAndSettle();

      expect(
        fakeSession.setNetworkSimulationCallCount,
        1,
        reason: 'Should commit to session exactly once on onChangeEnd',
      );
    });
  });
}
