// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/overlay/floating_overlay_manager.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';
import 'package:interceptly/src/ui/settings/settings_bottom_sheet.dart';

void main() {
  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  testWidgets(
    'SettingsBottomSheet slider uses InterceptlyTheme sliderTheme and ignores host SliderTheme',
    (tester) async {
      final engine = InterceptlyEngine();
      engine.setNetworkSimulation(
        const NetworkSimulationProfile(
          name: 'Custom',
          offline: false,
          latencyMs: 150,
          downloadKbps: 1024,
          uploadKbps: 512,
        ),
      );
      final controller = InterceptlyScopeController(engine: engine);
      addTearDown(controller.dispose);

      const hostActiveColor = Colors.purpleAccent;
      const hostThumbColor = Colors.lime;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            sliderTheme: const SliderThemeData(
              activeTrackColor: hostActiveColor,
              thumbColor: hostThumbColor,
            ),
          ),
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: const SettingsBottomSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final sliderThemes =
          tester.widgetList<SliderTheme>(find.byType(SliderTheme)).toList();

      expect(sliderThemes, isNotEmpty);
      for (final sliderTheme in sliderThemes) {
        expect(sliderTheme.data.activeTrackColor, isNot(hostActiveColor));
        expect(sliderTheme.data.thumbColor, isNot(hostThumbColor));

        expect(
          sliderTheme.data.activeTrackColor,
          InterceptlyTheme.colors.actionPrimary,
        );
        expect(
          sliderTheme.data.thumbColor,
          InterceptlyTheme.colors.actionPrimary,
        );
      }
    },
  );

  testWidgets(
    'SettingsBottomSheet toggles hide for session in FloatingOverlayManager',
    (tester) async {
      final engine = InterceptlyEngine();
      final controller = InterceptlyScopeController(engine: engine);
      addTearDown(controller.dispose);
      FloatingOverlayManager.instance.setHiddenForSession(false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: const SettingsBottomSheet(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hide for This Session'), findsOneWidget);
      expect(
          find.text('Hides bug button until next app launch'), findsOneWidget);
      expect(FloatingOverlayManager.instance.isHiddenForSession, isFalse);

      await tester.tap(find.text('Hide for This Session'));
      await tester.pumpAndSettle();

      expect(FloatingOverlayManager.instance.isHiddenForSession, isTrue);

      await tester.tap(find.text('Hide for This Session'));
      await tester.pumpAndSettle();

      expect(FloatingOverlayManager.instance.isHiddenForSession, isFalse);
    },
  );
}
