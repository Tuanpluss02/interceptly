import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/screens/interceptly_screen.dart';
import 'package:interceptly/src/ui/tabs/network_tab.dart';

void main() {
  group('InterceptlyScreen Bottom Navigation Bar', () {
    late InspectorSession session;

    setUp(() {
      session = InspectorSession();
    });

    tearDown(() async {
      await session.dispose();
    });

    testWidgets('renders single view with no bottom bar when isRealtimeActive is false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InterceptlyScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.byType(NetworkTab), findsOneWidget);
    });

    testWidgets('renders NavigationBar with REST and Realtime tabs when isRealtimeActive is true', (tester) async {
      session.configureSession(const InterceptlySettings(enableRealtime: true));

      await tester.pumpWidget(
        MaterialApp(
          home: InterceptlyScreen(session: session),
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

      final updatedNavBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(updatedNavBar.selectedIndex, equals(1));
    });

    testWidgets('dynamically shows NavigationBar when a realtime connection is recorded', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InterceptlyScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing);

      // Record a websocket connection
      session.recordRealtimeConnection(
        id: 'ws_auto_1',
        url: 'wss://realtime.example.com/stream',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('REST'), findsOneWidget);
      expect(find.text('Realtime'), findsOneWidget);

      session.closeRealtimeConnection('ws_auto_1');
      await tester.pumpAndSettle();
    });

    testWidgets('tab switching alternates between REST requests and WebSocket connections', (tester) async {
      session.configureSession(const InterceptlySettings(enableRealtime: true));
      session.recordPending(
        id: 'req_tab_1',
        method: 'GET',
        url: 'https://api.example.com/data',
        timestamp: DateTime(2026, 10, 14, 10, 0),
      );
      session.recordRealtimeConnection(
        id: 'ws_tab_1',
        url: 'wss://realtime.example.com/events',
        timestamp: DateTime(2026, 10, 14, 10, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: InterceptlyScreen(session: session),
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

      await session.clear();
      await tester.pump();
    });
  });
}
