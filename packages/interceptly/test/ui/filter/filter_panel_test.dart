import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/filter/filter_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FilterPanel domain list layout', () {
    testWidgets(
        'domain list container does not inherit bottom safe-area padding from MediaQuery',
        (tester) async {
      tester.view.devicePixelRatio = 3.0;
      tester.view.padding = const FakeViewPadding(bottom: 102);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => FilterPanel.show(
                  context: ctx,
                  currentFilter: RequestFilter(),
                  availableDomains: {'api.com'},
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

      final row = tester.getSize(
        find
            .ancestor(
              of: find.text('api.com'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      final card = tester.getSize(
        find
            .ancestor(
              of: find.text('api.com'),
              matching: find.byType(Container),
            )
            .first,
      );

      expect(
        card.height,
        row.height + 2,
        reason: 'only the 1px borders may add height around the domain row',
      );
    });
  });

  group('FilterPanel Redesign', () {
    testWidgets(
        'does not show Show errors only and allows toggling methods and applying filter',
        (tester) async {
      RequestFilter? applied;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => FilterPanel.show(
                  context: ctx,
                  currentFilter: RequestFilter(),
                  availableDomains: {
                    'api.github.com',
                    'stormx.dev',
                    'auth.example.com'
                  },
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
      expect(find.text('Show errors only'), findsNothing);

      await tester.tap(find.text('GET'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Apply Filter'));
      await tester.pumpAndSettle();

      expect(applied, isNotNull);
      expect(applied!.methods, isNot(contains('GET')));
      expect(applied!.methods, contains('POST'));
    });

    testWidgets('domain search field filters the list of available domains',
        (tester) async {
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

      await tester.enterText(find.byType(TextField), 'alpha');
      await tester.pumpAndSettle();

      expect(find.text('alpha.com'), findsOneWidget);
      expect(find.text('beta.com'), findsNothing);
    });

    testWidgets('Reset All resets all modified filter selections to defaults',
        (tester) async {
      RequestFilter? applied;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => FilterPanel.show(
                  context: ctx,
                  currentFilter: RequestFilter(methods: {'POST'}),
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
      expect(applied!.methods, isEmpty);
    });

    testWidgets(
        'prevents deselecting all status codes and disables Apply when no domains selected',
        (tester) async {
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

      await tester.tap(find.text('3xx Redirect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4xx Client Err'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5xx Server Err'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('2xx Success'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deselect All'));
      await tester.pumpAndSettle();

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
