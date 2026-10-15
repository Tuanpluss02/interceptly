import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/filter/filter_panel.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/screens/interceptly_screen.dart';
import 'package:interceptly/src/ui/settings/settings_bottom_sheet.dart';
import 'package:interceptly/src/ui/widgets/interceptly_confirm_dialog.dart';
import 'package:interceptly/src/ui/widgets/toast_notification.dart';

void main() {
  const hostPrimaryColor = Colors.purpleAccent;
  const hostCardColor = Colors.amber;
  const hostCanvasColor = Colors.teal;
  const hostDialogColor = Colors.deepOrange;

  final hostTheme = ThemeData(
    primaryColor: hostPrimaryColor,
    cardColor: hostCardColor,
    canvasColor: hostCanvasColor,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      primary: hostPrimaryColor,
      surface: hostCanvasColor,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: hostDialogColor,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: hostPrimaryColor,
      thumbColor: hostPrimaryColor,
    ),
  );

  group('Theme isolation tests', () {
    setUp(() async {
      await InspectorSession.resetForTesting();
    });

    tearDown(() async {
      await InspectorSession.resetForTesting();
    });

    testWidgets('InterceptlyScreen completely overrides host ThemeData',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: hostTheme,
          home: InterceptlyScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final scaffoldElement = tester.element(find.byType(Scaffold).first);
      final theme = Theme.of(scaffoldElement);

      expect(theme.primaryColor, isNot(hostPrimaryColor));
      expect(theme.colorScheme.primary, InterceptlyTheme.colors.actionPrimary);
      expect(theme.dialogTheme.backgroundColor, InterceptlyTheme.surface);
    });

    testWidgets('FilterPanel is isolated from host ThemeData', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: hostTheme,
          home: Scaffold(
            body: FilterPanel(
              currentFilter: RequestFilter(),
              availableDomains: const {'api.example.com'},
              onFilterChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final childElement = tester.element(
        find.descendant(
          of: find.byType(FilterPanel),
          matching: find.byType(FilledButton),
        ),
      );
      final theme = Theme.of(childElement);
      expect(theme.colorScheme.primary, InterceptlyTheme.colors.actionPrimary);
      expect(theme.colorScheme.primary, isNot(hostPrimaryColor));
    });

    testWidgets('InterceptlyConfirmDialog is isolated from host ThemeData',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: hostTheme,
          home: const Scaffold(
            body: InterceptlyConfirmDialog(
              title: 'Test Title',
              message: 'Test Message',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final childElement = tester.element(
        find.descendant(
          of: find.byType(InterceptlyConfirmDialog),
          matching: find.byType(ElevatedButton),
        ),
      );
      final theme = Theme.of(childElement);
      expect(theme.colorScheme.primary, InterceptlyTheme.colors.actionPrimary);
      expect(theme.colorScheme.primary, isNot(hostPrimaryColor));
    });

    testWidgets('SettingsBottomSheet is isolated from host ThemeData',
        (tester) async {
      final session = InspectorSession.instance;
      session.setNetworkSimulation(
        const NetworkSimulationProfile(
          name: 'Custom',
          offline: false,
          latencyMs: 100,
          downloadKbps: 1000,
          uploadKbps: 500,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: hostTheme,
          home: Scaffold(
            body: SettingsBottomSheet(session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final childElement = tester.element(
        find.descendant(
          of: find.byType(SettingsBottomSheet),
          matching: find.byType(Slider).first,
        ),
      );
      final theme = Theme.of(childElement);
      expect(theme.colorScheme.primary, InterceptlyTheme.colors.actionPrimary);
      expect(theme.colorScheme.primary, isNot(hostPrimaryColor));

      final sliderThemes =
          tester.widgetList<SliderTheme>(find.byType(SliderTheme)).toList();
      for (final st in sliderThemes) {
        expect(st.data.activeTrackColor, isNot(hostPrimaryColor));
        expect(st.data.activeTrackColor, InterceptlyTheme.colors.actionPrimary);
      }
    });

    testWidgets('ToastNotification is isolated from host ThemeData',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: hostTheme,
          home: const Scaffold(
            body: ToastNotification(message: 'Hello Interceptly'),
          ),
        ),
      );
      await tester.pump();

      final childElement = tester.element(
        find.descendant(
          of: find.byType(ToastNotification),
          matching: find.byType(Text),
        ),
      );
      final theme = Theme.of(childElement);
      expect(theme.colorScheme.primary, InterceptlyTheme.colors.actionPrimary);
      expect(theme.colorScheme.primary, isNot(hostPrimaryColor));

      await tester.pump(const Duration(seconds: 3));
    });
  });
}
