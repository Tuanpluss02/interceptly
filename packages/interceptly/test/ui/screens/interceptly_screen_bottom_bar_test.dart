// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';
import 'package:interceptly/src/ui/screens/interceptly_screen.dart';
import 'package:interceptly/src/ui/tabs/network_tab.dart';
import 'package:interceptly/src/ui/tabs/realtime_list_tab.dart';
import 'package:interceptly/src/ui/widgets/interceptly_text_field.dart';

void main() {
  group('InterceptlyScreen Bottom Navigation Bar', () {
    late InterceptlyEngine engine;
    late InterceptlyScopeController controller;

    setUp(() async {
      await Interceptly.resetForTesting();
      engine = InterceptlyEngine();
      controller = InterceptlyScopeController(engine: engine);
    });

    tearDown(() async {
      controller.dispose();
      await Interceptly.resetForTesting();
    });

    testWidgets(
        'renders single view with no bottom bar when isRealtimeActive is false',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InterceptlyScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.byType(NetworkTab), findsOneWidget);
    });

    testWidgets(
        'renders NavigationBar with REST and Realtime tabs when isRealtimeActive is true',
        (tester) async {
      engine.configure(const InterceptlySettings(enableRealtime: true));

      await tester.pumpWidget(
        MaterialApp(
          home: InterceptlyScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('REST'), findsOneWidget);
      expect(find.text('Realtime'), findsOneWidget);

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, equals(0));

      await tester.tap(find.text('Realtime'));
      await tester.pumpAndSettle();

      final updatedNavBar =
          tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(updatedNavBar.selectedIndex, equals(1));
    });

    testWidgets(
        'dynamically shows NavigationBar when a realtime connection is recorded',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InterceptlyScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing);

      engine.recordRealtimeConnection(
        id: 'ws_auto_1',
        url: 'wss://realtime.example.com/stream',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('REST'), findsOneWidget);
      expect(find.text('Realtime'), findsOneWidget);

      engine.closeRealtimeConnection('ws_auto_1');
      await tester.pumpAndSettle();
    });

    testWidgets(
        'tab switching alternates between REST requests and WebSocket connections',
        (tester) async {
      engine.configure(const InterceptlySettings(enableRealtime: true));
      engine.recordPending(
        id: 'req_tab_1',
        method: 'GET',
        url: 'https://api.example.com/data',
        timestamp: DateTime(2026, 10, 14, 10, 0),
      );
      engine.recordRealtimeConnection(
        id: 'ws_tab_1',
        url: 'wss://realtime.example.com/events',
        timestamp: DateTime(2026, 10, 14, 10, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: InterceptlyScreen(controller: controller),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('/data'), findsOneWidget);

      await tester.tap(find.text('Realtime'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('/events'), findsOneWidget);

      await engine.clear();
      await tester.pump();
    });

    testWidgets('realtime tab shows RealtimeListTab without search field',
        (tester) async {
      engine.configure(const InterceptlySettings(enableRealtime: true));

      await tester.pumpWidget(
        MaterialApp(
          home: InterceptlyScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.cable));
      await tester.pumpAndSettle();

      expect(find.byType(RealtimeListTab), findsOneWidget);
      expect(find.byType(InterceptlySearchField), findsNothing);
    });

    testWidgets('persists selected tab index across screen dismiss and re-open',
        (tester) async {
      engine.configure(const InterceptlySettings(enableRealtime: true));

      await tester.pumpWidget(
        MaterialApp(
          home: InterceptlyScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          equals(0));

      await tester.tap(find.text('Realtime'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          equals(1));

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(find.byType(InterceptlyScreen), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: InterceptlyScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          equals(1));
    });
  });
}
