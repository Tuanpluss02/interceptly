import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/tabs/quick_filter_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await InspectorSession.resetForTesting();
  });

  tearDown(() async {
    await InspectorSession.resetForTesting();
  });

  group('QuickFilterBar', () {
    testWidgets('renders quick filter chips and toggles onlyErrors filter',
        (tester) async {
      final session = InspectorSession();
      addTearDown(session.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickFilterBar(session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Errors'), findsOneWidget);
      expect(find.text('2xx'), findsOneWidget);
      expect(find.text('POST'), findsOneWidget);

      // Tap "Errors" chip
      await tester.tap(find.text('Errors'));
      await tester.pumpAndSettle();

      expect(session.filter.onlyErrors, isTrue);

      // Tap "All" chip
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      expect(session.filter.onlyErrors, isFalse);
      expect(session.filter.isEmpty, isTrue);
    });

    testWidgets('toggles 2xx status range filter and POST method filter',
        (tester) async {
      final session = InspectorSession();
      addTearDown(session.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickFilterBar(session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "2xx"
      await tester.tap(find.text('2xx'));
      await tester.pumpAndSettle();

      expect(session.filter.include2xx, isTrue);
      expect(session.filter.include3xx, isFalse);
      expect(session.filter.include4xx, isFalse);
      expect(session.filter.include5xx, isFalse);

      // Tap "POST"
      await tester.tap(find.text('POST'));
      await tester.pumpAndSettle();

      expect(session.filter.methods, equals({'POST'}));
    });
  });
}
