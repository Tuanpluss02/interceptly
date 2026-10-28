// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/ui/filter/filter_panel.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';
import 'package:interceptly/src/ui/screens/interceptly_screen.dart';
import 'package:interceptly/src/ui/tabs/realtime_list_tab.dart';
import 'package:interceptly/src/ui/widgets/filter_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InterceptlyEngine engine;
  late InterceptlyScopeController controller;

  setUp(() async {
    await Interceptly.resetForTesting();
    engine = InterceptlyEngine();
    controller = InterceptlyScopeController(engine: engine);
  });

  tearDown(() async {
    controller.dispose();
    await engine.clear();
    await engine.dispose();
    await Interceptly.resetForTesting();
  });

  group('REST vs Realtime availableDomains isolation', () {
    test('availableDomains excludes realtime-only domains', () {
      engine.recordRealtimeConnection(
        id: 'ws_1',
        url: 'wss://socket.only-realtime.com/feed',
        timestamp: DateTime(2026, 1, 1),
      );

      engine.recordPending(
        id: 'req_1',
        method: 'GET',
        url: 'https://api.only-rest.com/v1/users',
        timestamp: DateTime(2026, 1, 1),
      );

      expect(controller.availableDomains, contains('api.only-rest.com'));
      expect(controller.availableDomains,
          isNot(contains('socket.only-realtime.com')));
      expect(controller.availableDomains, equals({'api.only-rest.com'}));
    });

    test(
        'availableDomains includes shared domain having both REST and realtime',
        () {
      engine.recordPending(
        id: 'req_shared',
        method: 'GET',
        url: 'https://shared-domain.com/api/data',
        timestamp: DateTime(2026, 1, 1),
      );

      engine.recordRealtimeConnection(
        id: 'ws_shared',
        url: 'wss://shared-domain.com/live',
        timestamp: DateTime(2026, 1, 1),
      );

      engine.recordRealtimeConnection(
        id: 'ws_only',
        url: 'wss://socket.live.net/events',
        timestamp: DateTime(2026, 1, 1),
      );

      expect(controller.availableDomains, contains('shared-domain.com'));
      expect(controller.availableDomains, isNot(contains('socket.live.net')));
      expect(controller.availableDomains, equals({'shared-domain.com'}));
    });

    test('clearing REST logs removes shared domain when only realtime remains',
        () async {
      engine.recordPending(
        id: 'req_shared',
        method: 'POST',
        url: 'https://shared-domain.com/api/login',
        timestamp: DateTime(2026, 1, 1),
      );
      engine.recordRealtimeConnection(
        id: 'ws_shared',
        url: 'wss://shared-domain.com/live',
        timestamp: DateTime(2026, 1, 1),
      );

      expect(controller.availableDomains, equals({'shared-domain.com'}));

      await controller.clearRest();

      expect(controller.availableDomains, isEmpty);
    });

    test('clearing realtime logs preserves REST domains in availableDomains',
        () async {
      engine.recordPending(
        id: 'req_shared',
        method: 'POST',
        url: 'https://shared-domain.com/api/login',
        timestamp: DateTime(2026, 1, 1),
      );
      engine.recordRealtimeConnection(
        id: 'ws_shared',
        url: 'wss://shared-domain.com/live',
        timestamp: DateTime(2026, 1, 1),
      );
      engine.recordRealtimeConnection(
        id: 'ws_other',
        url: 'wss://other-rt.com/ws',
        timestamp: DateTime(2026, 1, 1),
      );

      await controller.clearRealtime();

      expect(controller.availableDomains, equals({'shared-domain.com'}));
    });

    testWidgets(
        'FilterPanel opened from NetworkTab does not show realtime-only domain',
        (tester) async {
      engine.configure(const InterceptlySettings(enableRealtime: true));
      engine.recordPending(
        id: 'req_1',
        method: 'GET',
        url: 'https://api.example.com/items',
        timestamp: DateTime(2026, 1, 1),
      );
      engine.recordRealtimeConnection(
        id: 'ws_1',
        url: 'wss://socket.realtime-only.com/feed',
        timestamp: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: InterceptlyScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilterBadge));
      await tester.pumpAndSettle();

      expect(find.byType(FilterPanel), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(FilterPanel),
              matching: find.text('api.example.com')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(FilterPanel),
              matching: find.text('socket.realtime-only.com')),
          findsNothing);

      await engine.clear();
      await tester.pump();
    });

    testWidgets(
        'RealtimeListTab is not filtered by REST domain or method filter',
        (tester) async {
      engine.configure(const InterceptlySettings(enableRealtime: true));
      engine.recordPending(
        id: 'req_1',
        method: 'GET',
        url: 'https://api.example.com/items',
        timestamp: DateTime(2026, 1, 1),
      );
      engine.recordRealtimeConnection(
        id: 'ws_1',
        url: 'wss://socket.realtime-only.com/feed',
        timestamp: DateTime(2026, 1, 1),
      );

      controller.applyFilter(RequestFilter(
        domains: {'api.example.com'},
        methods: {'POST'},
        include2xx: true,
        include3xx: false,
        include4xx: false,
        include5xx: false,
      ));

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
      await tester.pumpAndSettle();

      expect(find.text('/feed'), findsOneWidget);

      await engine.clear();
      await tester.pump();
    });
  });
}
