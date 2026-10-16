import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';
import 'package:interceptly/src/ui/tabs/network_tab.dart';
import 'package:interceptly/src/ui/tabs/quick_filter_bar.dart';
import 'package:interceptly/src/ui/tabs/rest_log_item.dart';

void main() {
  group('NetworkTab REST-only', () {
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

    testWidgets('NetworkTab rest-only has no realtime branching',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkTab(session: session),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('/items'), findsOneWidget);
      expect(find.byType(QuickFilterBar), findsOneWidget);
      expect(find.byType(RestLogItem), findsOneWidget);
      expect(find.text('/feed'), findsNothing);
    });

    testWidgets('empty state shows REST empty message', (tester) async {
      final emptySession = InspectorSession();
      addTearDown(emptySession.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkTab(session: emptySession),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No network requests yet.'), findsOneWidget);
    });

    testWidgets('tapping REST request opens RequestDetailPage', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkTab(session: session),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('/items'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(RequestDetailPage), findsOneWidget);
    });
  });
}
