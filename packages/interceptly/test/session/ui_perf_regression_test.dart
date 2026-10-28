/// UI rendering performance regressions.
///
/// Covers master-search debounce, realtime per-row ticker disposal,
/// and singleton toast queue behavior.

library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';
import 'package:interceptly/src/ui/tabs/network_tab.dart';
import 'package:interceptly/src/ui/tabs/realtime_list_tab.dart';
import 'package:interceptly/src/ui/widgets/toast_notification.dart';

void main() {
  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    ToastNotification.dispose();
    await Interceptly.resetForTesting();
  });

  group('UI perf regressions', () {
    testWidgets('master search debounces rapid keystrokes', (tester) async {
      final engine = InterceptlyEngine();
      final controller = InterceptlyScopeController(engine: engine);
      addTearDown(controller.dispose);
      addTearDown(engine.dispose);

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
      await tester.pumpAndSettle();

      final field = find.byType(TextField).first;
      await tester.enterText(field, 'h');
      await tester.enterText(field, 'he');
      await tester.enterText(field, 'hello');
      await tester.pump(const Duration(milliseconds: 100));
      final earlyQuery = controller.masterQuery;
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(controller.masterQuery, 'hello');
      expect(earlyQuery, isNot('hello'));
    });

    testWidgets('realtime tab disposes per-row ticker', (tester) async {
      final engine = InterceptlyEngine();
      final controller = InterceptlyScopeController(engine: engine);
      addTearDown(controller.dispose);
      addTearDown(engine.dispose);
      engine.recordRealtimeConnection(
        id: 'ws_live',
        url: 'wss://api.example.com/socket',
      );
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
      expect(find.byType(RealtimeListTab), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('toast queue keeps single visible toast', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      final context = tester.element(find.byType(SizedBox));
      ToastNotification.show('first', contextHint: context);
      await tester.pump();
      ToastNotification.show('second', contextHint: context);
      await tester.pump();
      expect(find.text('second'), findsOneWidget);
      expect(find.text('first'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      ToastNotification.dispose();
      await tester.pump();
    });
  });
}
