import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/detail/realtime_detail_page.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';
import 'package:interceptly/src/ui/tabs/network_tab.dart';
import 'package:interceptly/src/ui/tabs/request_log_item.dart';

void main() {
  group('NetworkTab Protocol Filtering', () {
    late InspectorSession session;

    setUp(() {
      session = InspectorSession();
      session.recordPending(
        id: 'req_1',
        method: 'GET',
        url: 'https://api.example.com/items',
        timestamp: DateTime(2026, 10, 14, 10, 0, 0),
      );
      session.recordRealtimeConnection(
        id: 'ws_1',
        url: 'wss://socket.example.com/feed',
        timestamp: DateTime(2026, 10, 14, 10, 1, 0),
      );
    });

    tearDown(() {
      session.dispose();
    });

    testWidgets('NetworkProtocol.rest displays only HTTP/REST requests', (tester) async {
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('/items'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RequestLogItem),
          matching: find.text('GET'),
        ),
        findsOneWidget,
      );

      expect(find.text('/feed'), findsNothing);
      expect(find.text('WS'), findsNothing);
    });

    testWidgets('NetworkProtocol.realtime displays only WebSocket connections', (tester) async {
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('/feed'), findsOneWidget);
      expect(find.text('WS'), findsOneWidget);

      expect(find.text('/items'), findsNothing);
      expect(find.text('GET'), findsNothing);
    });

    testWidgets('NetworkProtocol.all displays both HTTP and WebSocket entries', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkTab(
              session: session,
              protocol: NetworkProtocol.all,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('/items'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RequestLogItem),
          matching: find.text('GET'),
        ),
        findsOneWidget,
      );
      expect(find.text('/feed'), findsOneWidget);
      expect(find.text('WS'), findsOneWidget);
    });

    testWidgets('NetworkProtocol.realtime empty state shows custom empty message', (tester) async {
      final emptySession = InspectorSession();
      addTearDown(emptySession.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkTab(
              session: emptySession,
              protocol: NetworkProtocol.realtime,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No WebSocket connections yet.'), findsOneWidget);
    });

    testWidgets('NetworkTab ticks live duration second-by-second for active realtime connection',
        (tester) async {
      final session = InspectorSession();
      addTearDown(session.dispose);

      var currentTime = DateTime(2026, 1, 1, 10, 0, 0);
      session.recordRealtimeConnection(
        id: 'ws-live-ticker',
        url: 'wss://example.com/live',
        timestamp: currentTime,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkTab(
              session: session,
              protocol: NetworkProtocol.realtime,
              nowProvider: () => currentTime,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('0ms'), findsOneWidget);

      // Advance by 4 seconds
      currentTime = currentTime.add(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('4s'), findsOneWidget);

      // Close the connection
      session.closeRealtimeConnection(
        'ws-live-ticker',
        closeCode: 1000,
        closeReason: 'done',
      );
      await tester.pumpAndSettle();

      expect(find.text('CLOSED'), findsOneWidget);
    });

    testWidgets('tapping REST request opens RequestDetailPage', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkTab(
              session: session,
              protocol: NetworkProtocol.all,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('/items'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(RequestDetailPage), findsOneWidget);
      expect(find.byType(RealtimeDetailPage), findsNothing);
    });

    testWidgets('tapping WebSocket connection opens RealtimeDetailPage directly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkTab(
              session: session,
              protocol: NetworkProtocol.all,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('/feed'));
      await tester.pumpAndSettle();

      expect(find.byType(RealtimeDetailPage), findsOneWidget);
      expect(find.byType(RequestDetailPage), findsNothing);
    });
  });
}
