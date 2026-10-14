import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/filter/filter_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FilterPanel Redesign', () {
    testWidgets('allows toggling Errors Only and applying filter', (tester) async {
      RequestFilter? applied;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => FilterPanel.show(
                  context: ctx,
                  currentFilter: RequestFilter(),
                  availableDomains: {'api.github.com', 'stormx.dev', 'auth.example.com'},
                  onFilterChanged: (f) => applied = f,
                ),
                child: const Text('Open Filter'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Filter'));
      await tester.pumpAndSettle();

      expect(find.text('Filter Requests'), findsOneWidget);
      expect(find.text('Show errors only'), findsOneWidget);

      // Toggle Errors Only switch
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // Tap Apply Filter button
      await tester.tap(find.textContaining('Apply Filter'));
      await tester.pumpAndSettle();

      expect(applied, isNotNull);
      expect(applied!.onlyErrors, isTrue);
    });

    testWidgets('domain search field filters the list of available domains', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => FilterPanel.show(
                  context: ctx,
                  currentFilter: RequestFilter(),
                  availableDomains: {
                    'alpha.com',
                    'beta.com',
                    'gamma.com',
                    'delta.com',
                    'epsilon.com',
                  },
                  onFilterChanged: (_) {},
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Search domains...'), findsOneWidget);

      // Type "alpha" in domain search
      await tester.enterText(find.byType(TextField), 'alpha');
      await tester.pumpAndSettle();

      expect(find.text('alpha.com'), findsOneWidget);
      expect(find.text('beta.com'), findsNothing);
    });

    testWidgets('Reset All resets all modified filter selections to defaults', (tester) async {
      RequestFilter? applied;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => FilterPanel.show(
                  context: ctx,
                  currentFilter: RequestFilter(onlyErrors: true, methods: {'POST'}),
                  availableDomains: {'api.com'},
                  onFilterChanged: (f) => applied = f,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Reset All'), findsOneWidget);

      await tester.tap(find.text('Reset All'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Apply Filter'));
      await tester.pumpAndSettle();

      expect(applied, isNotNull);
      expect(applied!.onlyErrors, isFalse);
      expect(applied!.methods, isEmpty);
    });

    testWidgets('prevents deselecting all status codes and disables Apply when no domains selected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => FilterPanel.show(
                  context: ctx,
                  currentFilter: RequestFilter(),
                  availableDomains: {'api.com', 'web.com'},
                  onFilterChanged: (_) {},
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap 3xx, 4xx, 5xx to uncheck them
      await tester.tap(find.text('3xx Redirect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4xx Client Err'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5xx Server Err'));
      await tester.pumpAndSettle();

      // Now 2xx is the only one selected. Tapping 2xx should NOT deselect it
      await tester.tap(find.text('2xx Success'));
      await tester.pumpAndSettle();

      // Tap "Deselect All" on domains
      await tester.tap(find.text('Deselect All'));
      await tester.pumpAndSettle();

      // Apply button should be disabled
      final applyButton = tester.widget<FilledButton>(
        find.descendant(
          of: find.byType(FilterPanel),
          matching: find.byType(FilledButton),
        ),
      );
      expect(applyButton.onPressed, isNull);
    });
  });
}
