import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/realtime_frame.dart';
import 'package:interceptly/src/model/search_match_scope.dart';
import 'package:interceptly/src/ui/tabs/request_log_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildItem({
    String method = 'GET',
    String url = 'https://api.example.com/v1/users?query=search_term',
    String time = '11:20:00',
    String duration = '25ms',
    int status = 200,
    bool hasError = false,
    bool isPending = false,
    int responseSizeBytes = 1024,
    bool isSelectionMode = false,
    bool isSelected = false,
    Set<SearchMatchScope>? searchScopes,
    String? highlightQuery,
    bool isRealtime = false,
    RealtimeFrameCounts? realtimeFrameCounts,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: RequestLogItem(
          method: method,
          url: url,
          time: time,
          duration: duration,
          status: status,
          hasError: hasError,
          isPending: isPending,
          responseSizeBytes: responseSizeBytes,
          isSelectionMode: isSelectionMode,
          isSelected: isSelected,
          searchScopes: searchScopes,
          highlightQuery: highlightQuery,
          isRealtime: isRealtime,
          realtimeFrameCounts: realtimeFrameCounts,
          onTap: onTap ?? () {},
          onLongPress: onLongPress ?? () {},
        ),
      ),
    );
  }

  group('RequestLogItem Widget Tests', () {
    testWidgets('renders basic method, path, host and status pill',
        (tester) async {
      await tester.pumpWidget(buildItem());

      expect(find.text('GET'), findsOneWidget);
      expect(find.text('/v1/users?query=search_term'), findsOneWidget);
      expect(find.text('api.example.com'), findsOneWidget);
      expect(find.text('200'), findsOneWidget);
      expect(find.textContaining('11:20:00 · 25ms'), findsOneWidget);
    });

    testWidgets('displays match scope badges when searchScopes is non-empty',
        (tester) async {
      await tester.pumpWidget(
        buildItem(
          searchScopes: {
            SearchMatchScope.url,
            SearchMatchScope.headers,
            SearchMatchScope.body,
            SearchMatchScope.error,
          },
          highlightQuery: 'users',
        ),
      );

      expect(find.text('URL'), findsOneWidget);
      expect(find.text('Headers'), findsOneWidget);
      expect(find.text('Body'), findsOneWidget);
      expect(find.text('Error'), findsOneWidget);
    });

    testWidgets('does not show scope badges when searchScopes is null or empty',
        (tester) async {
      await tester.pumpWidget(buildItem(searchScopes: null));
      expect(find.text('URL'), findsNothing);
      expect(find.text('Headers'), findsNothing);
      expect(find.text('Body'), findsNothing);
      expect(find.text('Error'), findsNothing);

      await tester.pumpWidget(buildItem(searchScopes: const {}));
      expect(find.text('URL'), findsNothing);
    });

    testWidgets('highlights matched query in URL and host via RichText',
        (tester) async {
      await tester.pumpWidget(
        buildItem(
          url: 'https://example.com/search_keyword',
          highlightQuery: 'search',
        ),
      );

      final richTextWidgets =
          tester.widgetList<RichText>(find.byType(RichText));
      expect(richTextWidgets, isNotEmpty);

      final hasHighlight = richTextWidgets.any((rt) {
        final span = rt.text as TextSpan;
        bool found = false;
        span.visitChildren((child) {
          if (child is TextSpan &&
              child.text == 'search' &&
              child.style?.fontWeight == FontWeight.w700) {
            found = true;
            return false;
          }
          return true;
        });
        return found;
      });
      expect(hasHighlight, isTrue);
    });

    testWidgets('invokes onTap and onLongPress callbacks correctly',
        (tester) async {
      var tapped = false;
      var longPressed = false;

      await tester.pumpWidget(
        buildItem(
          onTap: () => tapped = true,
          onLongPress: () => longPressed = true,
        ),
      );

      await tester.tap(find.byType(RequestLogItem));
      expect(tapped, isTrue);

      await tester.longPress(find.byType(RequestLogItem));
      expect(longPressed, isTrue);
    });

    testWidgets('renders CONNECTED badge and frame counts for active realtime connection',
        (tester) async {
      await tester.pumpWidget(
        buildItem(
          method: 'WS',
          url: 'wss://realtime.example.com/socket',
          time: '12:00:00',
          duration: '45s',
          status: 0,
          isPending: true,
          isRealtime: true,
          realtimeFrameCounts: const RealtimeFrameCounts(incoming: 12, outgoing: 5),
        ),
      );

      expect(find.text('WS'), findsOneWidget);
      expect(find.text('CONNECTED'), findsOneWidget);
      expect(find.textContaining('12:00:00 · 45s · ↓ 12  ↑ 5'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('renders CLOSED badge for normally closed realtime connection',
        (tester) async {
      await tester.pumpWidget(
        buildItem(
          method: 'WS',
          url: 'wss://realtime.example.com/socket',
          time: '12:00:00',
          duration: '2m 15s',
          status: 1000,
          isPending: false,
          isRealtime: true,
          realtimeFrameCounts: const RealtimeFrameCounts(incoming: 20, outgoing: 10),
        ),
      );

      expect(find.text('CLOSED'), findsOneWidget);
      expect(find.text('1000'), findsNothing);
      expect(find.textContaining('12:00:00 · 2m 15s · ↓ 20  ↑ 10'), findsOneWidget);
    });

    testWidgets('renders DROPPED badge for abnormally closed realtime connection',
        (tester) async {
      await tester.pumpWidget(
        buildItem(
          method: 'WS',
          url: 'wss://realtime.example.com/socket',
          time: '12:00:00',
          duration: '30s',
          status: 1006,
          hasError: true,
          isPending: false,
          isRealtime: true,
          realtimeFrameCounts: const RealtimeFrameCounts(incoming: 3, outgoing: 1),
        ),
      );

      expect(find.text('DROPPED'), findsOneWidget);
      expect(find.text('1006'), findsNothing);
      expect(find.textContaining('12:00:00 · 30s · ↓ 3  ↑ 1'), findsOneWidget);
    });

    testWidgets('metadata line width is not constrained by status badge width',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildItem(
          method: 'WS',
          url: 'wss://realtime.example.com/socket/v1/stream',
          time: '12:00:00',
          duration: '1h 30m 15s',
          status: 0,
          isPending: true,
          isRealtime: true,
          realtimeFrameCounts:
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
