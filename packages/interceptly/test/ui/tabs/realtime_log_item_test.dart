import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/realtime_frame.dart';
import 'package:interceptly/src/ui/tabs/realtime_log_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildItem({
    String method = 'WS',
    String url = 'wss://realtime.example.com/socket',
    String time = '12:00:00',
    String duration = '45s',
    int status = 0,
    bool hasError = false,
    bool isPending = true,
    RealtimeFrameCounts? frameCounts,
    ValueNotifier<RealtimeFrameCounts>? frameCountsNotifier,
    VoidCallback? onTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: RealtimeLogItem(
          method: method,
          url: url,
          time: time,
          duration: duration,
          status: status,
          hasError: hasError,
          isPending: isPending,
          frameCounts: frameCounts,
          frameCountsNotifier: frameCountsNotifier,
          onTap: onTap ?? () {},
        ),
      ),
    );
  }

  group('RealtimeLogItem Widget Tests', () {
    testWidgets('renders CONNECTED badge and frame counts for active connection',
        (tester) async {
      await tester.pumpWidget(
        buildItem(
          duration: '45s',
          frameCounts:
              const RealtimeFrameCounts(incoming: 12, outgoing: 5),
        ),
      );

      expect(find.text('WS'), findsOneWidget);
      expect(find.text('CONNECTED'), findsOneWidget);
      expect(find.textContaining('12:00:00 · 45s · ↓ 12  ↑ 5'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('200'), findsNothing);
    });

    testWidgets('renders CLOSED badge for normally closed connection',
        (tester) async {
      await tester.pumpWidget(
        buildItem(
          duration: '2m 15s',
          status: 1000,
          isPending: false,
          frameCounts:
              const RealtimeFrameCounts(incoming: 20, outgoing: 10),
        ),
      );

      expect(find.text('CLOSED'), findsOneWidget);
      expect(find.text('1000'), findsNothing);
      expect(find.textContaining('12:00:00 · 2m 15s · ↓ 20  ↑ 10'),
          findsOneWidget);
    });

    testWidgets('renders DROPPED badge for abnormally closed connection',
        (tester) async {
      await tester.pumpWidget(
        buildItem(
          duration: '30s',
          status: 1006,
          hasError: true,
          isPending: false,
          frameCounts:
              const RealtimeFrameCounts(incoming: 3, outgoing: 1),
        ),
      );

      expect(find.text('DROPPED'), findsOneWidget);
      expect(find.text('1006'), findsNothing);
      expect(find.textContaining('12:00:00 · 30s · ↓ 3  ↑ 1'), findsOneWidget);
    });

    testWidgets('updates frame counts from notifier without rebuild',
        (tester) async {
      final notifier = ValueNotifier<RealtimeFrameCounts>(
        const RealtimeFrameCounts(incoming: 1, outgoing: 0),
      );
      addTearDown(notifier.dispose);

      await tester.pumpWidget(
        buildItem(frameCountsNotifier: notifier),
      );
      expect(find.textContaining('↓ 1  ↑ 0'), findsOneWidget);

      notifier.value = const RealtimeFrameCounts(incoming: 7, outgoing: 3);
      await tester.pump();
      expect(find.textContaining('↓ 7  ↑ 3'), findsOneWidget);
    });

    testWidgets('invokes onTap callback correctly', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        buildItem(onTap: () => tapped = true),
      );

      await tester.tap(find.byType(RealtimeLogItem));
      expect(tapped, isTrue);
    });

    testWidgets('metadata line width is not constrained by status badge width',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildItem(
          url: 'wss://realtime.example.com/socket/v1/stream',
          duration: '1h 30m 15s',
          frameCounts:
              const RealtimeFrameCounts(incoming: 1234, outgoing: 5678),
        ),
      );

      final badgeFinder = find.text('CONNECTED');
      final metaFinder =
          find.textContaining('12:00:00 · 1h 30m 15s · ↓ 1234  ↑ 5678');
      expect(badgeFinder, findsOneWidget);
      expect(metaFinder, findsOneWidget);

      final badgeRenderBox = tester.renderObject(badgeFinder) as RenderBox;
      final metaRenderBox = tester.renderObject(metaFinder) as RenderBox;

      expect(metaRenderBox.size.width, greaterThan(220));
      expect(badgeRenderBox.size.width, greaterThan(50));
    });
  });
}
