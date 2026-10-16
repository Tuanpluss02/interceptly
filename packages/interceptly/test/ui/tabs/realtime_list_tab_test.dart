import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/detail/realtime_detail_page.dart';
import 'package:interceptly/src/ui/tabs/quick_filter_bar.dart';
import 'package:interceptly/src/ui/tabs/realtime_list_tab.dart';
import 'package:interceptly/src/ui/widgets/filter_badge.dart';
import 'package:interceptly/src/ui/widgets/interceptly_text_field.dart';

void main() {
  group('RealtimeListTab', () {
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

    testWidgets('realtime list shows only realtime, no search or filter UI',
        (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: RealtimeListTab(session: session))));
      await tester.pump();
      expect(find.text('/feed'), findsOneWidget);
      expect(find.text('/items'), findsNothing);
      expect(find.byType(InterceptlySearchField), findsNothing);
      expect(find.byType(QuickFilterBar), findsNothing);
      expect(find.byType(FilterBadge), findsNothing);
    });

    testWidgets('empty session shows websocket empty message', (tester) async {
      final emptySession = InspectorSession();
      addTearDown(emptySession.dispose);

      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: RealtimeListTab(session: emptySession))));
      await tester.pump();

      expect(find.text('No WebSocket connections yet.'), findsOneWidget);
    });

    testWidgets('tapping realtime row opens RealtimeDetailPage',
        (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: RealtimeListTab(session: session))));
      await tester.pump();

      await tester.tap(find.text('/feed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(RealtimeDetailPage), findsOneWidget);
    });

    testWidgets('ticks live duration forward for active connections',
        (tester) async {
      var currentTime = DateTime(2026, 10, 14, 10, 1, 3);

      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: RealtimeListTab(
                  session: session, nowProvider: () => currentTime))));
      await tester.pump();

      expect(find.textContaining('3s'), findsOneWidget);

      currentTime = currentTime.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('4s'), findsOneWidget);
    });
  });
}
