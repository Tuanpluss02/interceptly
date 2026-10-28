// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/ui/detail/realtime_detail_page.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';
import 'package:interceptly/src/ui/tabs/quick_filter_bar.dart';
import 'package:interceptly/src/ui/tabs/realtime_list_tab.dart';
import 'package:interceptly/src/ui/widgets/filter_badge.dart';
import 'package:interceptly/src/ui/widgets/interceptly_text_field.dart';

void main() {
  group('RealtimeListTab', () {
    late InterceptlyEngine engine;
    late InterceptlyScopeController controller;

    setUp(() async {
      await Interceptly.resetForTesting();
      engine = InterceptlyEngine();
      controller = InterceptlyScopeController(engine: engine);
      engine.recordPending(
        id: 'req_1',
        method: 'GET',
        url: 'https://api.example.com/items',
        timestamp: DateTime(2026, 10, 14, 10, 0, 0),
      );
      engine.recordRealtimeConnection(
        id: 'ws_1',
        url: 'wss://socket.example.com/feed',
        timestamp: DateTime(2026, 10, 14, 10, 1, 0),
      );
    });

    tearDown(() async {
      controller.dispose();
      await Interceptly.resetForTesting();
    });

    testWidgets('realtime list shows only realtime, no search or filter UI',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: const RealtimeListTab(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('/feed'), findsOneWidget);
      expect(find.text('/items'), findsNothing);
      expect(find.byType(InterceptlySearchField), findsNothing);
      expect(find.byType(QuickFilterBar), findsNothing);
      expect(find.byType(FilterBadge), findsNothing);
    });

    testWidgets('empty session shows websocket empty message', (tester) async {
      final emptyEngine = InterceptlyEngine();
      final emptyController = InterceptlyScopeController(engine: emptyEngine);
      addTearDown(emptyController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: emptyController,
              child: const RealtimeListTab(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('No WebSocket connections yet.'), findsOneWidget);
    });

    testWidgets('tapping realtime row opens RealtimeDetailPage',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: const RealtimeListTab(),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('/feed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(RealtimeDetailPage), findsOneWidget);
    });

    testWidgets('ticks live duration forward for active connections',
        (tester) async {
      var currentTime = DateTime(2026, 10, 14, 10, 1, 3);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: RealtimeListTab(nowProvider: () => currentTime),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('3s'), findsOneWidget);

      currentTime = currentTime.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('4s'), findsOneWidget);
    });

    testWidgets('cancels duration ticker when connection closes',
        (tester) async {
      var currentTime = DateTime(2026, 10, 14, 10, 1, 3);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: RealtimeListTab(nowProvider: () => currentTime),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('3s'), findsOneWidget);

      // Close the connection
      engine.closeRealtimeConnection('ws_1');
      await tester.pump();

      final entry = controller.entries.firstWhere((e) => e.id == 'ws_1');
      expect(entry.statusCode, equals(1000));

      // Advance time and pump - ticker was cancelled by didUpdateWidget
      currentTime = currentTime.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 2));

      expect(find.textContaining('13s'), findsNothing);
    });
  });
}
