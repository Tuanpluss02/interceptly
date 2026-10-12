import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
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
}
