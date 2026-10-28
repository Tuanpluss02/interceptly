import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/request_record.dart';
import 'package:interceptly/src/ui/detail/detail_search.dart';
import 'package:interceptly/src/ui/detail/detail_tabs_builder.dart';

DetailTabsBuilder _buildTabs(RequestRecord record) {
  return DetailTabsBuilder(
    record: record,
    matches: const <DetailMatch>[],
    activeGlobalIndex: null,
    query: '',
    urlDecodeEnabled: false,
    tryParseJson: (raw) => raw,
  );
}

RequestRecord _buildRecord({String? errorType, String? errorMessage}) {
  return RequestRecord(
    id: 'overview_1',
    method: 'GET',
    url: 'https://api.example.com/v1/items?page=2',
    statusCode: 200,
    durationMs: 42,
    requestSizeBytes: 128,
    responseSizeBytes: 512,
    timestamp: DateTime.utc(2026, 1, 1, 12),
    requestHeaders: const {'accept': 'application/json'},
    responseHeaders: const {'content-type': 'application/json'},
    errorType: errorType,
    errorMessage: errorMessage,
  );
}

void main() {
  group('Overview tab text selection', () {
    testWidgets('wraps overview values in a SelectionArea', (tester) async {
      final tabs = _buildTabs(_buildRecord());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: tabs.buildOverviewTab()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.ancestor(
          of: find.text('https://api.example.com/v1/items?page=2'),
          matching: find.byType(SelectionArea),
        ),
        findsOneWidget,
        reason: 'overview values must be selectable',
      );
      expect(
        find.ancestor(
          of: find.text('42 ms'),
          matching: find.byType(SelectionArea),
        ),
        findsOneWidget,
      );
    });

    testWidgets('long press on an overview value shows the copy toolbar',
        (tester) async {
      final tabs = _buildTabs(_buildRecord());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: tabs.buildOverviewTab()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(
        find.text('https://api.example.com/v1/items?page=2'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsOneWidget);
    });
  });
}
