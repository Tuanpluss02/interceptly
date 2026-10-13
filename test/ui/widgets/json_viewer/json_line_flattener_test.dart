import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_expansion_state.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_line_flattener.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_search.dart';

void main() {
  const baseStyle = TextStyle(fontSize: 12, height: 1.5);

  group('JsonLineFlattener.countExpandedLines', () {
    test('scalars return 1', () {
      expect(JsonLineFlattener.countExpandedLines('hello'), 1);
      expect(JsonLineFlattener.countExpandedLines(123), 1);
      expect(JsonLineFlattener.countExpandedLines(true), 1);
      expect(JsonLineFlattener.countExpandedLines(null), 1);
    });

    test('empty list and map return 1', () {
      expect(JsonLineFlattener.countExpandedLines([]), 1);
      expect(JsonLineFlattener.countExpandedLines({}), 1);
    });

    test('calculates correct line count for nested structures', () {
      final data = {
        'a': [1, 2],
        'b': {'c': 3},
      };
      expect(JsonLineFlattener.countExpandedLines(data), 9);
    });
  });

  group('JsonExpansionState', () {
    test('defaults: <= 20 children expanded, > 20 children collapsed', () {
      final state = JsonExpansionState();
      expect(state.isExpanded(r'$.small', 5), isTrue);
      expect(state.isExpanded(r'$.exact', 20), isTrue);
      expect(state.isExpanded(r'$.large', 21), isFalse);
    });

    test('forceCollapse collapses everything except root', () {
      final state = JsonExpansionState()..forceCollapse = true;
      expect(state.isExpanded(r'$', 50), isTrue);
      expect(state.isExpanded(r'$.child', 5), isFalse);
    });

    test('toggle flips state and records user collapse', () {
      final state = JsonExpansionState();
      expect(state.isExpanded(r'$.node', 5), isTrue);

      state.toggle(r'$.node', 5);
      expect(state.isExpanded(r'$.node', 5), isFalse);
      expect(state.isUserCollapsed(r'$.node'), isTrue);

      state.toggle(r'$.node', 5);
      expect(state.isExpanded(r'$.node', 5), isTrue);
      expect(state.isUserCollapsed(r'$.node'), isFalse);
    });
  });

  group('JsonLineFlattener.flatten', () {
    test('advances realLine correctly when collapsing a node', () {
      final data = {
        'folded': [1, 2, 3],
        'next': 'hello',
      };
      final expansion = JsonExpansionState()..toggle(r'$.folded', 3);

      final flattener = JsonLineFlattener(
        expansion: expansion,
        activeGlobalIndex: null,
        matchCounts: null,
        lineCountMemo: null,
        baseTextStyle: baseStyle,
      );

      final lines = flattener.flatten(data);
      expect(lines.length, 4);
      expect(lines[0].realLineNumber, 1);
      expect(lines[1].realLineNumber, 2);
      expect(lines[1].collapsible?.isExpanded, isFalse);
      expect(lines[2].realLineNumber, 7);
      expect(lines[3].realLineNumber, 8);
    });

    test('auto-expands collapsed node containing active search match', () {
      final data = {
        'items': List.generate(25, (i) => 'item_$i'),
      };
      final expansion = JsonExpansionState();
      const query = 'item_10';
      final matchCounts = JsonSearch.matchCountsByPath(data, query);

      final flattener = JsonLineFlattener(
        expansion: expansion,
        activeGlobalIndex: 0,
        matchCounts: matchCounts,
        lineCountMemo: null,
        baseTextStyle: baseStyle,
      );

      final lines = flattener.flatten(data, query: query);
      expect(expansion.isExpanded(r'$.items', 25), isTrue);
      expect(expansion.searchAutoExpandedForTest.contains(r'$.items'), isTrue);

      final matchLine = lines.firstWhere((l) => l.hasActiveMatch);
      expect(matchLine.spans.any((s) => s.text?.contains('item_10') ?? false),
          isTrue);
    });

    test('does NOT auto-expand node explicitly collapsed by user', () {
      final data = {
        'items': ['val1', 'val2'],
      };
      final expansion = JsonExpansionState()..toggle(r'$.items', 2);
      expect(expansion.isUserCollapsed(r'$.items'), isTrue);

      const query = 'val1';
      final matchCounts = JsonSearch.matchCountsByPath(data, query);

      final flattener = JsonLineFlattener(
        expansion: expansion,
        activeGlobalIndex: 0,
        matchCounts: matchCounts,
        lineCountMemo: null,
        baseTextStyle: baseStyle,
      );

      final lines = flattener.flatten(data, query: query);
      expect(expansion.isExpanded(r'$.items', 2), isFalse);
      expect(lines.length, 3);
    });

    test('splits multiline string into separate JsonLines', () {
      final data = {'text': 'line1\nline2\nline3'};
      final expansion = JsonExpansionState();
      final flattener = JsonLineFlattener(
        expansion: expansion,
        activeGlobalIndex: null,
        matchCounts: null,
        lineCountMemo: null,
        baseTextStyle: baseStyle,
      );

      final lines = flattener.flatten(data);
      expect(lines.length, 5);
    });
  });
}
