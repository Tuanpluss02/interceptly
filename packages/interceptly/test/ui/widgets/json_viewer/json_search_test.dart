import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_search.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer_style.dart';

void main() {
  group('JsonSearch.formatData', () {
    test('formats null as "null"', () {
      expect(JsonSearch.formatData(null), 'null');
    });

    test('pretty-prints json string', () {
      const input = '{"a":1,"b":true}';
      expect(
        JsonSearch.formatData(input),
        '{\n  "a": 1,\n  "b": true\n}',
      );
    });

    test('returns invalid json string unchanged', () {
      const input = '{invalid json';
      expect(JsonSearch.formatData(input), input);
    });

    test('pretty-prints Map directly', () {
      final input = {'key': 'value'};
      expect(
        JsonSearch.formatData(input),
        '{\n  "key": "value"\n}',
      );
    });
  });

  group('JsonSearch.countMatches and countIn', () {
    test('returns 0 on empty query', () {
      expect(JsonSearch.countMatches({'foo': 'bar'}, ''), 0);
      expect(JsonSearch.countIn('hello world', ''), 0);
    });

    test('counts case-insensitively in keys and string values including quotes',
        () {
      final data = {
        'Foo': 'bar',
        'items': ['FOO', 123, false, null],
      };
      expect(JsonSearch.countMatches(data, 'foo'), 2);
    });

    test('counts in numbers, booleans and null', () {
      final data = {
        'num': 42,
        'flag': true,
        'empty': null,
      };
      expect(JsonSearch.countMatches(data, '42'), 1);
      expect(JsonSearch.countMatches(data, 'true'), 1);
      expect(JsonSearch.countMatches(data, 'null'), 1);
    });

    test('handles regex special chars literally without crash', () {
      final data = {r'$schema': 'http://example.com/[0-9]/'};
      expect(JsonSearch.countMatches(data, r'$schema'), 1);
      expect(JsonSearch.countMatches(data, '[0-9]'), 1);
    });
  });

  group('JsonSearch.matchCountsByPath', () {
    test('indexes match counts per JSON path', () {
      final data = {
        'name': 'search',
        'nested': {
          'title': 'search result',
        },
      };
      final counts = JsonSearch.matchCountsByPath(data, 'search');
      expect(counts[r'$'], 2);
      expect(counts[r'$.name'], 1);
      expect(counts[r'$.nested'], 1);
      expect(counts[r'$.nested.title'], 1);
    });
  });

  group('JsonSearch.buildHighlightedSpans and spanHasActiveHighlight', () {
    const baseColor = Color(0xFFFFFFFF);

    test('returns plain span when query not present', () {
      final spans = JsonSearch.buildHighlightedSpans(
        'hello world',
        'xyz',
        0,
        null,
        baseColor,
      );
      expect(spans.length, 1);
      expect(spans.first.text, 'hello world');
      expect(spans.first.style?.backgroundColor, isNull);
      expect(JsonSearch.spanHasActiveHighlight(spans.first), isFalse);
    });

    test('highlights matches and marks activeGlobalIndex with activeHighlight',
        () {
      final spans = JsonSearch.buildHighlightedSpans(
        'foo and foo',
        'foo',
        5,
        6,
        baseColor,
      );

      expect(spans.length, 3);
      expect(spans[0].text, 'foo');
      expect(spans[0].style?.backgroundColor, JsonViewerColors.highlight);
      expect(JsonSearch.spanHasActiveHighlight(spans[0]), isFalse);

      expect(spans[1].text, ' and ');
      expect(spans[1].style?.backgroundColor, isNull);

      expect(spans[2].text, 'foo');
      expect(spans[2].style?.backgroundColor, JsonViewerColors.activeHighlight);
      expect(JsonSearch.spanHasActiveHighlight(spans[2]), isTrue);
    });

    test('spanHasActiveHighlight checks recursively in children', () {
      final parentSpan = TextSpan(
        text: 'parent',
        children: [
          const TextSpan(text: 'child 1'),
          const TextSpan(
            text: 'child 2',
            style: TextStyle(backgroundColor: JsonViewerColors.activeHighlight),
          ),
        ],
      );
      expect(JsonSearch.spanHasActiveHighlight(parentSpan), isTrue);
    });
  });
}
