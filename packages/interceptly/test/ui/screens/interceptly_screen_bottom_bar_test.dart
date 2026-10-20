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

      // Switch to Realtime tab
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

      // Record a websocket connection
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

      // Tab 0 (REST) is default: /data should be in view, /events should not be rendered in the active view
      expect(find.text('/data'), findsOneWidget);

      // Tap Realtime tab (Tab 1)
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

      // 1. Open InterceptlyScreen
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

      // 2. User taps 'Realtime' tab
      await tester.tap(find.text('Realtime'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          equals(1));

      // 3. User exits screen (simulating popping route/closing overlay)
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(find.byType(InterceptlyScreen), findsNothing);

      // 4. User opens InterceptlyScreen again with same controller
      await tester.pumpWidget(
        MaterialApp(
          home: InterceptlyScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      // Must restore Realtime tab (index 1), NOT reset to 0 (REST)
      expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          equals(1));
    });
  });
}
