import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  });
}
