// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';
import 'package:interceptly/src/ui/tabs/network_tab.dart';
import 'package:interceptly/src/ui/tabs/quick_filter_bar.dart';
import 'package:interceptly/src/ui/tabs/rest_log_item.dart';

void main() {
  group('NetworkTab REST-only', () {
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

    testWidgets('NetworkTab rest-only has no realtime branching',
        (tester) async {
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('/items'), findsOneWidget);
      expect(find.byType(QuickFilterBar), findsOneWidget);
      expect(find.byType(RestLogItem), findsOneWidget);
      expect(find.text('/feed'), findsNothing);
    });

    testWidgets('empty state shows REST empty message', (tester) async {
      final emptyEngine = InterceptlyEngine();
      final emptyController = InterceptlyScopeController(engine: emptyEngine);
      addTearDown(emptyController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: emptyController,
              child: const NetworkTab(),
            ),
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
            body: InterceptlyScope(
              controller: controller,
              child: const NetworkTab(),
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
    });
  });
}
