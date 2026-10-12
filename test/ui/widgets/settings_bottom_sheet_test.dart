import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/overlay/floating_overlay_manager.dart';
import 'package:interceptly/src/ui/settings/settings_bottom_sheet.dart';

void main() {
  testWidgets(
    'SettingsBottomSheet slider uses InterceptlyTheme sliderTheme and ignores host SliderTheme',
    (tester) async {
      final session = InspectorSession();
      // Set to custom so throttling sliders are rendered
      session.setNetworkSimulation(
        const NetworkSimulationProfile(
          name: 'Custom',
          offline: false,
          latencyMs: 150,
          downloadKbps: 1024,
          uploadKbps: 512,
        ),
      );

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
            body: SettingsBottomSheet(session: session),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final sliderThemes =
          tester.widgetList<SliderTheme>(find.byType(SliderTheme)).toList();

      expect(sliderThemes, isNotEmpty);
      for (final sliderTheme in sliderThemes) {
        // Must NOT match host app colors
        expect(sliderTheme.data.activeTrackColor, isNot(hostActiveColor));
        expect(sliderTheme.data.thumbColor, isNot(hostThumbColor));

        // Must match InterceptlyTheme colors
        expect(
          sliderTheme.data.activeTrackColor,
          InterceptlyTheme.colors.actionPrimary,
        );
        expect(
          sliderTheme.data.thumbColor,
          InterceptlyTheme.colors.actionSecondary,
        );
      }
    },
  );

  testWidgets(
    'SettingsBottomSheet toggles hide for session in FloatingOverlayManager',
    (tester) async {
      final session = InspectorSession();
      FloatingOverlayManager.instance.setHiddenForSession(false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsBottomSheet(session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hide for This Session'), findsOneWidget);
      expect(
          find.text('Hides bug button until next app launch'), findsOneWidget);
      expect(FloatingOverlayManager.instance.isHiddenForSession, isFalse);

      // Tap the tile to hide
      await tester.tap(find.text('Hide for This Session'));
      await tester.pumpAndSettle();

      expect(FloatingOverlayManager.instance.isHiddenForSession, isTrue);

      // Tap again to restore
      await tester.tap(find.text('Hide for This Session'));
      await tester.pumpAndSettle();

      expect(FloatingOverlayManager.instance.isHiddenForSession, isFalse);
    },
  );
}
