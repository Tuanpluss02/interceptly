import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/screens/interceptly_screen.dart';

/// The AppBar delete button clears only the visible tab.
void main() {
  group('InterceptlyScreen scoped clear', () {
    late InspectorSession session;

    setUp(() {
      session = InspectorSession();
      session.configureSession(const InterceptlySettings(enableRealtime: true));
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

    tearDown(() async {
      await session.dispose();
    });

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InterceptlyScreen(session: session),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> tapDeleteAndConfirm(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Clear'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    List<String> ids() => session.entries.map((e) => e.id).toList();

    testWidgets('delete on REST tab keeps realtime connections',
        (tester) async {
      await pumpScreen(tester);
      expect(find.byType(NavigationBar), findsOneWidget);

      await tapDeleteAndConfirm(tester);

      expect(ids(), isNot(contains('req_1')));
      expect(ids(), contains('ws_1'));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('delete on Realtime tab keeps REST requests', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Realtime'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tapDeleteAndConfirm(tester);

      expect(ids(), isNot(contains('ws_1')));
      expect(ids(), contains('req_1'));
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
