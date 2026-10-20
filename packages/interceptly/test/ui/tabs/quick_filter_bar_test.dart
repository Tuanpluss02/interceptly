// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';
import 'package:interceptly/src/ui/tabs/quick_filter_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('QuickFilterBar', () {
    testWidgets('renders quick filter chips and toggles onlyErrors filter',
        (tester) async {
      final engine = InterceptlyEngine();
      final controller = InterceptlyScopeController(engine: engine);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: const QuickFilterBar(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Errors'), findsOneWidget);
      expect(find.text('2xx'), findsOneWidget);
      expect(find.text('POST'), findsOneWidget);

      await tester.tap(find.text('Errors'));
      await tester.pumpAndSettle();

      expect(controller.filter.onlyErrors, isTrue);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      expect(controller.filter.onlyErrors, isFalse);
      expect(controller.filter.isEmpty, isTrue);
    });

    testWidgets('toggles 2xx status range filter and POST method filter',
        (tester) async {
      final engine = InterceptlyEngine();
      final controller = InterceptlyScopeController(engine: engine);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: const QuickFilterBar(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('2xx'));
      await tester.pumpAndSettle();

      expect(controller.filter.include2xx, isTrue);
      expect(controller.filter.include3xx, isFalse);
      expect(controller.filter.include4xx, isFalse);
      expect(controller.filter.include5xx, isFalse);

      await tester.tap(find.text('POST'));
      await tester.pumpAndSettle();

      expect(controller.filter.methods, equals({'POST'}));
    });
  });
}
