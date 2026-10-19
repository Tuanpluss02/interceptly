// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';
import 'package:interceptly/src/ui/tabs/network_tab.dart';
import 'package:interceptly/src/ui/tabs/quick_filter_bar.dart';
import 'package:interceptly/src/ui/widgets/filter_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('NetworkTab Filter Integration', () {
    testWidgets('shows FilterBadge and QuickFilterBar', (tester) async {
      final engine = InterceptlyEngine();
      final controller = InterceptlyScopeController(engine: engine);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: const NetworkTab(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FilterBadge), findsOneWidget);
      expect(find.byType(QuickFilterBar), findsOneWidget);
    });

    testWidgets('FilterBadge reflects active filter count reactively',
        (tester) async {
      final engine = InterceptlyEngine();
      final controller = InterceptlyScopeController(engine: engine);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: const NetworkTab(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final badgeInitial = tester.widget<FilterBadge>(find.byType(FilterBadge));
      expect(badgeInitial.activeFiltersCount, equals(0));

      // Apply filter
      controller
          .applyFilter(RequestFilter(onlyErrors: true, methods: {'POST'}));
      await tester.pumpAndSettle();

      final badgeActive = tester.widget<FilterBadge>(find.byType(FilterBadge));
      expect(badgeActive.activeFiltersCount, equals(2));
    });

    testWidgets('always shows QuickFilterBar even with realtime entries',
        (tester) async {
      final engine = InterceptlyEngine();
      final controller = InterceptlyScopeController(engine: engine);
      addTearDown(controller.dispose);
      engine.recordRealtimeConnection(
        id: 'ws_1',
        url: 'wss://socket.example.com/feed',
        timestamp: DateTime(2026, 10, 14, 10, 1, 0),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: const NetworkTab(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(QuickFilterBar), findsOneWidget);
      expect(find.text('/feed'), findsNothing);
    });
  });
}
