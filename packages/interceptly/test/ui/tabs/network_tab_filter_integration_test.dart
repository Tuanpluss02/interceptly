import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/tabs/network_tab.dart';
import 'package:interceptly/src/ui/tabs/quick_filter_bar.dart';
import 'package:interceptly/src/ui/widgets/filter_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await InspectorSession.resetForTesting();
  });

  tearDown(() async {
    await InspectorSession.resetForTesting();
  });

  group('NetworkTab Filter Integration', () {
    testWidgets('shows FilterBadge and QuickFilterBar for REST protocol',
        (tester) async {
      final session = InspectorSession();
      addTearDown(session.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkTab(
              session: session,
              protocol: NetworkProtocol.rest,
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
      final session = InspectorSession();
      addTearDown(session.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkTab(
              session: session,
              protocol: NetworkProtocol.rest,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final badgeInitial = tester.widget<FilterBadge>(find.byType(FilterBadge));
      expect(badgeInitial.activeFiltersCount, equals(0));

      // Apply filter
      session.applyFilter(RequestFilter(onlyErrors: true, methods: {'POST'}));
      await tester.pumpAndSettle();

      final badgeActive = tester.widget<FilterBadge>(find.byType(FilterBadge));
      expect(badgeActive.activeFiltersCount, equals(2));
    });

    testWidgets('hides QuickFilterBar for Realtime protocol', (tester) async {
      final session = InspectorSession();
      addTearDown(session.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkTab(
              session: session,
              protocol: NetworkProtocol.realtime,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(QuickFilterBar), findsNothing);
    });
  });
}
