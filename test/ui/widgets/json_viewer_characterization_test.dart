import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';

/// Characterization test: snapshots the flattened line model produced by
/// [JsonViewer] for a set of representative fixtures, so internal refactors
/// can be verified to be behavior-preserving.
///
/// Regenerate the golden (only when a behavior change is intended) with:
/// `UPDATE_JSON_VIEWER_GOLDEN=1 flutter test test/ui/widgets/json_viewer_characterization_test.dart`
void main() {
  const goldenPath = 'test/ui/widgets/goldens/json_viewer_lines.txt';

  String describeSpan(TextSpan span) {
    final buffer = StringBuffer();
    final bg = span.style?.backgroundColor;
    final text = span.text ?? '';
    if (bg == InterceptlyGlobalColor.orange) {
      buffer.write('<<$text>>');
    } else if (bg != null) {
      buffer.write('[$text]');
    } else {
      buffer.write(text);
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) buffer.write(describeSpan(child));
    }
    return buffer.toString();
  }

  String serialize(List<dynamic> lines) {
    final buffer = StringBuffer();
    for (final dynamic line in lines) {
      final spans = (line.spans as List).cast<TextSpan>();
      final text = spans.map(describeSpan).join();
      final dynamic c = line.collapsible;
      final fold =
          c == null ? '-' : '${c.path},${c.childCount},${c.isExpanded}';
      buffer.writeln(
        '${line.indentLevel}|${line.realLineNumber}|$fold|'
        '${line.hasActiveMatch}|$text',
      );
    }
    return buffer.toString();
  }

  Future<String> render(
    WidgetTester tester,
    String name,
    dynamic data, {
    String? query,
    int? activeIndex,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: JsonViewer(
              key: ValueKey(name),
              data: data,
              searchQuery: query,
              activeGlobalIndex: activeIndex,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(JsonViewer));
    final lines = state.memoLinesForTest as List<dynamic>;
    return '=== $name ===\n${serialize(lines)}';
  }

  testWidgets('flattened line model matches golden snapshot', (tester) async {
    final mixed = <String, dynamic>{
      'id': 42,
      'ratio': 3.5,
      'active': true,
      'deleted': false,
      'note': null,
      'emptyList': <dynamic>[],
      'emptyMap': <String, dynamic>{},
      'tags': ['a', 'b', 'target'],
      'nested': {
        'level2': {
          'target': 'deep target value',
          'list': [1, 2, 3],
        },
      },
      'bigList': [for (int i = 0; i < 25; i++) 'item_$i'],
    };

    final strings = <String, dynamic>{
      'multiline': 'first line\nsecond target line\nthird line',
      'long': 'x' * 2500,
      'after': 'end',
    };

    final huge = <String, dynamic>{
      for (int i = 0; i < 400; i++) 'k$i': {'a': i, 'b': 'v$i', 'c': true},
    };

    final out = StringBuffer()
      ..write(await render(tester, 'mixed_plain', mixed))
      ..write(await render(tester, 'mixed_search', mixed,
          query: 'target', activeIndex: 2))
      ..write(await render(tester, 'mixed_search_autoexpand', mixed,
          query: 'item_2', activeIndex: 5))
      ..write(await render(tester, 'strings_search', strings,
          query: 'line', activeIndex: 1))
      ..write(await render(tester, 'huge_force_collapse', huge))
      ..write(await render(tester, 'huge_search', huge,
          query: 'v39', activeIndex: 0))
      ..write(await render(tester, 'json_string_root', '{"a":[1,2],"b":"c"}'))
      ..write(await render(tester, 'scalar_root', 'plain text value'));

    final actual = out.toString();
    final file = File(goldenPath);
    if (Platform.environment['UPDATE_JSON_VIEWER_GOLDEN'] == '1' ||
        !file.existsSync()) {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(actual);
    }
    expect(actual, equals(file.readAsStringSync()));
  });
}
