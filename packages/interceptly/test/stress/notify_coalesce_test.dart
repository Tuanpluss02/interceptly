// ignore_for_file: invalid_use_of_internal_member
@Tags(['stress'])
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/ui/detail/realtime_messages_tab.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_expansion_state.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_line_flattener.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('Task 7 Perf Hardening: Coalesce Notify & Search Debounce', () {
    test('coalesces 1000 burst capture ready notifications to <= 20 calls', () {
      fakeAsync((async) {
        final engine = InterceptlyEngine(
          settings: const InterceptlySettings(maxEntries: 2000),
        );
        addTearDown(engine.dispose);

        var notifyCount = 0;
        engine.addListener(() => notifyCount++);

        for (var i = 0; i < 1000; i++) {
          engine.recordPending(
            id: 'req_burst_$i',
            method: 'GET',
            url: 'https://api.example.com/items/$i',
            timestamp: DateTime(2026, 1, 1).add(Duration(milliseconds: i)),
          );

          if (i % 20 == 0) {
            async.elapse(const Duration(milliseconds: 1));
          }
        }

        async.elapse(const Duration(milliseconds: 100));

        expect(engine.entriesVersion, 1000);
        expect(engine.totalEntries, 1000);
        expect(
          notifyCount,
          lessThanOrEqualTo(20),
          reason:
              '1000 rapid entries should be throttled/coalesced into <= 20 notifications',
        );
      });
    });

    testWidgets(
        'realtime messages search input debounces filtering by 150-200ms',
        (tester) async {
      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);

      for (var i = 0; i < 10; i++) {
        await engine.recordRealtimeFrame(
          RealtimeFrame.text(
            id: 'frame_$i',
            sessionId: 'ws_debounce_test',
            direction: FrameDirection.incoming,
            text: i == 3 ? 'needle_special_payload' : 'regular_message_$i',
          ),
        );
      }

      final controller = InterceptlyScopeController(engine: engine);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: const RealtimeMessagesTab(
                sessionId: 'ws_debounce_test',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('regular_message_0'), findsOneWidget);
      expect(find.textContaining('needle_special_payload'), findsOneWidget);

      final searchField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Search messages...',
      );
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'needle');
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.textContaining('regular_message_0'),
        findsOneWidget,
        reason:
            'At 50ms, search query should not filter yet due to 150-200ms debounce',
      );

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.textContaining('needle_special_payload'), findsOneWidget);
      expect(find.textContaining('regular_message_0'), findsNothing);
    });

    test(
        'large JSON 5k lines ensures lines efficiently and preserves invariants',
        () async {
      final largeData = <String, dynamic>{
        'items': List.generate(
          1000,
          (i) => {
            'id': i,
            'name': 'Item $i',
            'active': i.isEven,
            'score': i * 1.5,
          },
        ),
      };

      final stopwatch = Stopwatch()..start();
      final analysis =
          JsonLineFlattener.countLinesAndMatches(largeData, 'item 42');
      stopwatch.stop();

      expect(analysis.lineCount, greaterThanOrEqualTo(5000));
      expect(analysis.matchCounts, isNotEmpty);
      debugPrint(
          '[Perf Profile] countLinesAndMatches for ${analysis.lineCount} lines took: ${stopwatch.elapsedMilliseconds}ms');

      final flattenerStopwatch = Stopwatch()..start();
      final expansion = JsonExpansionState()
        ..forceCollapse = false
        ..setExplicitState(r'$.items', true);
      final flattener = JsonLineFlattener(
        expansion: expansion,
        activeGlobalIndex: null,
        matchCounts: analysis.matchCounts,
        lineCountMemo: null,
        baseTextStyle: const TextStyle(fontSize: 12),
      );
      final lines = flattener.flatten(largeData, query: 'item 42');
      flattenerStopwatch.stop();

      expect(lines.length, greaterThanOrEqualTo(5000));
      expect(lines.first.realLineNumber, equals(1));
      expect(lines.last.realLineNumber, equals(analysis.lineCount));
      debugPrint(
          '[Perf Profile] flattener.flatten for ${lines.length} lines took: ${flattenerStopwatch.elapsedMilliseconds}ms');

      final asyncLines = await JsonLineFlattener.flattenAsync(
        data: largeData,
        expansion: expansion,
        baseTextStyle: const TextStyle(fontSize: 12),
        query: 'item 42',
      );
      expect(asyncLines.length, equals(lines.length));
    });
  });
}
