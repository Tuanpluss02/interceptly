// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/ui/overlay/floating_overlay_manager.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';
import 'package:interceptly/src/ui/settings/settings_bottom_sheet.dart';

class _FakeScopeController extends InterceptlyScopeController {
  _FakeScopeController({required super.engine});
  int setNetworkSimulationCallCount = 0;

  @override
  void setNetworkSimulation(NetworkSimulationProfile profile) {
    setNetworkSimulationCallCount++;
    super.setNetworkSimulation(profile);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    FloatingOverlayManager.instance.detach();
    await Interceptly.resetForTesting();
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
      final matchCountFirst = navKey.currentState!.widget.observers
          .where((o) => identical(o, obs))
          .length;
      expect(matchCountFirst, 1);

      FloatingOverlayManager.instance.attach(
        navigatorKey: navKey,
        showFloatingButton: true,
      );
      await tester.pumpAndSettle();

      final matchCountSecond = navKey.currentState!.widget.observers
          .where((o) => identical(o, obs))
          .length;
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
    testWidgets(
        'slider drag updates local state and commits only on onChangeEnd',
        (tester) async {
      final engine = InterceptlyEngine();
      engine.setNetworkSimulation(const NetworkSimulationProfile(
        name: 'Custom',
        offline: false,
        latencyMs: 100,
        downloadKbps: 1000,
        uploadKbps: 500,
      ));
      final fakeScope = _FakeScopeController(engine: engine);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: fakeScope,
              child: const SettingsBottomSheet(),
            ),
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
        fakeScope.setNetworkSimulationCallCount,
        0,
        reason: 'Should not commit to session during drag ticks (onChanged)',
      );

      slider.onChangeEnd!(300);
      await tester.pumpAndSettle();

      expect(
        fakeScope.setNetworkSimulationCallCount,
        1,
        reason: 'Should commit to session exactly once on onChangeEnd',
      );
    });
  });
}
