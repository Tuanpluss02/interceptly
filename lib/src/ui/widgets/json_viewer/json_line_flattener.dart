import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

import 'json_expansion_state.dart';
import 'json_line.dart';
import 'json_search.dart';
import 'json_viewer_style.dart';

/// Flattens hierarchical JSON-like data into a sequential list of [JsonLine]s.
///
/// Handles indentation, line numbering in the fully-expanded document,
/// search term highlighting, collapsible region detection and auto-expansion.
class JsonLineFlattener {
  final JsonExpansionState expansion;
  final int? activeGlobalIndex;
  final Map<String, int>? matchCounts;
  final Expando<int>? lineCountMemo;
  final TextStyle baseTextStyle;

  const JsonLineFlattener({
    required this.expansion,
    required this.activeGlobalIndex,
    required this.matchCounts,
    required this.lineCountMemo,
    required this.baseTextStyle,
  });

  /// Flattens [data] into visual [JsonLine]s.
  List<JsonLine> flatten(
    dynamic data, {
    String? query,
    int matchOffset = 0,
  }) {
    final lines = <JsonLine>[];
    _flatten(
      value: data,
      key: null,
      isLast: true,
      indent: 0,
      path: r'$',
      query: query,
      matchOffset: matchOffset,
      realLine: 1,
      output: lines,
    );
    return lines;
  }

  /// Counts how many lines [value] would occupy when **fully expanded**.
  ///
  /// Used to assign correct real line numbers when a collapsible node
  /// is folded — the line numbers skip the hidden range, matching
  /// VSCode behavior.
  static int countExpandedLines(
    dynamic value, [
    Expando<int>? memo,
  ]) {
    if (value == null || value is bool || value is num || value is String) {
      return 1;
    }
    if (memo != null && (value is List || value is Map)) {
      final cached = memo[value];
      if (cached != null) return cached;
    }

    int count = 1;
    if (value is List) {
      if (value.isEmpty) {
        count = 1;
      } else {
        int total = 2;
        for (final item in value) {
          total += countExpandedLines(item, memo);
        }
        count = total;
      }
    } else if (value is Map) {
      if (value.isEmpty) {
        count = 1;
      } else {
        int total = 2;
        for (final entry in value.entries) {
          total += countExpandedLines(entry.value, memo);
        }
        count = total;
      }
    }

    if (memo != null && (value is List || value is Map)) {
      memo[value] = count;
    }
    return count;
  }

  TextSpan _bracketSpan(String text) => TextSpan(
        text: text,
        style: baseTextStyle.copyWith(color: JsonViewerColors.punctuation),
      );

  /// Recursively flatten [value] into sequential [JsonLine] objects.
  ({int matchOffset, int nextRealLine}) _flatten({
    required dynamic value,
    required String? key,
    required bool isLast,
    required int indent,
    required String path,
    required String? query,
    required int matchOffset,
    required int realLine,
    required List<JsonLine> output,
  }) {
    int currentOffset = matchOffset;

    // ── Build key spans ──
    final keySpans = <TextSpan>[];
    if (key != null) {
      final keyText = '"$key"';
      if (query != null) {
        keySpans.addAll(
          JsonSearch.buildHighlightedSpans(
            keyText,
            query,
            currentOffset,
            activeGlobalIndex,
            JsonViewerColors.key,
          ),
        );
        currentOffset += JsonSearch.countIn(keyText, query);
      } else {
        keySpans.add(TextSpan(
          text: keyText,
          style: baseTextStyle.copyWith(color: JsonViewerColors.key),
        ));
      }
      keySpans.add(TextSpan(
        text: ': ',
        style: baseTextStyle.copyWith(color: JsonViewerColors.punctuation),
      ));
    }

    final commaSpan = isLast
        ? null
        : TextSpan(
            text: ',',
            style: baseTextStyle.copyWith(color: JsonViewerColors.punctuation),
          );

    // ── Scalars ──
    if (value == null) {
      return _emitLeaf(
          output,
          indent,
          keySpans,
          'null',
          JsonViewerColors.nullValue,
          currentOffset,
          query,
          commaSpan,
          realLine);
    }
    if (value is bool) {
      return _emitLeaf(output, indent, keySpans, value.toString(),
          JsonViewerColors.boolean, currentOffset, query, commaSpan, realLine);
    }
    if (value is num) {
      return _emitLeaf(output, indent, keySpans, value.toString(),
          JsonViewerColors.number, currentOffset, query, commaSpan, realLine);
    }
    if (value is String) {
      if (value.contains('\n') || value.length > 2000) {
        return _emitChunkedString(
          output: output,
          indent: indent,
          keySpans: keySpans,
          value: value,
          commaSpan: commaSpan,
          currentOffset: currentOffset,
          query: query,
          realLine: realLine,
        );
      }
      return _emitLeaf(output, indent, keySpans, '"$value"',
          JsonViewerColors.string, currentOffset, query, commaSpan, realLine);
    }

    // ── List ──
    if (value is List) {
      if (value.isEmpty) {
        output.add(JsonLine(
          indentLevel: indent,
          realLineNumber: realLine,
          spans: [
            ...keySpans,
            _bracketSpan('[]'),
            if (commaSpan != null) commaSpan,
          ],
        ));
        return (matchOffset: currentOffset, nextRealLine: realLine + 1);
      }
      return _emitCollapsible(
        output: output,
        indent: indent,
        keySpans: keySpans,
        openBracket: '[',
        closeBracket: ']',
        commaSpan: commaSpan,
        path: path,
        childCount: value.length,
        query: query,
        matchOffset: currentOffset,
        realLine: realLine,
        rawValue: value,
        children: value.asMap().entries.map(
              (e) => _ChildEntry(
                key: null,
                value: e.value,
                isLast: e.key == value.length - 1,
                childPath: '$path[${e.key}]',
              ),
            ),
      );
    }

    // ── Map ──
    if (value is Map) {
      if (value.isEmpty) {
        output.add(JsonLine(
          indentLevel: indent,
          realLineNumber: realLine,
          spans: [
            ...keySpans,
            _bracketSpan('{}'),
            if (commaSpan != null) commaSpan,
          ],
        ));
        return (matchOffset: currentOffset, nextRealLine: realLine + 1);
      }
      final entries = value.entries.toList();
      return _emitCollapsible(
        output: output,
        indent: indent,
        keySpans: keySpans,
        openBracket: '{',
        closeBracket: '}',
        commaSpan: commaSpan,
        path: path,
        childCount: entries.length,
        query: query,
        matchOffset: currentOffset,
        realLine: realLine,
        rawValue: value,
        children: entries.asMap().entries.map(
              (e) => _ChildEntry(
                key: e.value.key.toString(),
                value: e.value.value,
                isLast: e.key == entries.length - 1,
                childPath: '$path.${e.value.key}',
              ),
            ),
      );
    }

    // ── Fallback ──
    return _emitLeaf(
        output,
        indent,
        keySpans,
        value.toString(),
        JsonViewerColors.punctuation,
        currentOffset,
        query,
        commaSpan,
        realLine);
  }

  /// Emit a single leaf line (scalar value).
  ({int matchOffset, int nextRealLine}) _emitLeaf(
    List<JsonLine> output,
    int indent,
    List<TextSpan> keySpans,
    String valueText,
    Color valueColor,
    int matchOffset,
    String? query,
    TextSpan? commaSpan,
    int realLine,
  ) {
    final spans = <TextSpan>[...keySpans];
    bool hasActiveMatch = false;

    if (query != null) {
      final valueSpans = JsonSearch.buildHighlightedSpans(
        valueText,
        query,
        matchOffset,
        activeGlobalIndex,
        valueColor,
      );
      final activeInValue = valueSpans.any(
        (s) => s.style?.backgroundColor == JsonViewerColors.activeHighlight,
      );
      final activeInKey = keySpans.any(JsonSearch.spanHasActiveHighlight);
      hasActiveMatch = activeInValue || activeInKey;
      spans.addAll(valueSpans);
      matchOffset += JsonSearch.countIn(valueText, query);
    } else {
      spans.add(TextSpan(
        text: valueText,
        style: baseTextStyle.copyWith(color: valueColor),
      ));
    }

    if (commaSpan != null) spans.add(commaSpan);

    output.add(JsonLine(
      indentLevel: indent,
      realLineNumber: realLine,
      spans: spans,
      hasActiveMatch: hasActiveMatch,
    ));

    return (matchOffset: matchOffset, nextRealLine: realLine + 1);
  }

  ({int matchOffset, int nextRealLine}) _emitChunkedString({
    required List<JsonLine> output,
    required int indent,
    required List<TextSpan> keySpans,
    required String value,
    required TextSpan? commaSpan,
    required int currentOffset,
    required String? query,
    required int realLine,
  }) {
    final splitLines = value.split('\n');
    final rawLines = <String>[];
    const maxLineLen = 1000;
    for (final l in splitLines) {
      if (l.length <= maxLineLen) {
        rawLines.add(l);
      } else {
        for (int i = 0; i < l.length; i += maxLineLen) {
          rawLines.add(l.substring(i, math.min(i + maxLineLen, l.length)));
        }
      }
    }

    int lineNum = realLine;
    int offset = currentOffset;

    for (int i = 0; i < rawLines.length; i++) {
      final lineStr = rawLines[i];
      final isFirst = i == 0;
      final isLastLine = i == rawLines.length - 1;

      final chunkSpans = <TextSpan>[
        if (isFirst) ...keySpans,
      ];

      final prefix = isFirst ? '"' : '';
      final suffix = isLastLine ? '"' : '';
      final displayText = '$prefix$lineStr$suffix';

      bool hasActiveMatch = false;
      if (query != null) {
        final highlighted = JsonSearch.buildHighlightedSpans(
          displayText,
          query,
          offset,
          activeGlobalIndex,
          JsonViewerColors.string,
        );
        final activeInText = highlighted.any(
          (s) => s.style?.backgroundColor == JsonViewerColors.activeHighlight,
        );
        final activeInKey =
            isFirst && keySpans.any(JsonSearch.spanHasActiveHighlight);
        hasActiveMatch = activeInText || activeInKey;
        chunkSpans.addAll(highlighted);
        offset += JsonSearch.countIn(displayText, query);
      } else {
        chunkSpans.add(TextSpan(
          text: displayText,
          style: baseTextStyle.copyWith(color: JsonViewerColors.string),
        ));
      }

      if (isLastLine && commaSpan != null) {
        chunkSpans.add(commaSpan);
      }

      output.add(JsonLine(
        indentLevel: isFirst ? indent : indent + 1,
        realLineNumber: lineNum,
        spans: chunkSpans,
        hasActiveMatch: hasActiveMatch,
      ));

      lineNum++;
    }

    return (matchOffset: offset, nextRealLine: lineNum);
  }

  /// Emit lines for a collapsible Map or List.
  ///
  /// When expanded: header + children + closing bracket.
  /// When collapsed: single line with `{ … }` / `[ … ]`.
  ///
  /// Collapsed nodes advance [realLine] by the number of lines the
  /// fully-expanded subtree would occupy so siblings get correct
  /// real line numbers.
  ({int matchOffset, int nextRealLine}) _emitCollapsible({
    required List<JsonLine> output,
    required int indent,
    required List<TextSpan> keySpans,
    required String openBracket,
    required String closeBracket,
    required TextSpan? commaSpan,
    required String path,
    required int childCount,
    required String? query,
    required int matchOffset,
    required int realLine,
    required dynamic rawValue,
    required Iterable<_ChildEntry> children,
  }) {
    int currentOffset = matchOffset;

    // Auto-expand when the active search match falls inside this subtree
    // and the user hasn't manually collapsed it.
    if (query != null &&
        activeGlobalIndex != null &&
        !expansion.isUserCollapsed(path)) {
      final totalValueMatches = matchCounts?[path] ?? 0;
      if (totalValueMatches > 0 &&
          activeGlobalIndex! >= currentOffset &&
          activeGlobalIndex! < currentOffset + totalValueMatches) {
        if (!expansion.isExpanded(path, childCount)) {
          expansion.markAutoExpanded(path);
        }
      }
    }

    final expanded = expansion.isExpanded(path, childCount);
    final activeInKey = keySpans.any(JsonSearch.spanHasActiveHighlight);

    if (expanded) {
      // Header: "key": {
      output.add(JsonLine(
        indentLevel: indent,
        realLineNumber: realLine,
        spans: [...keySpans, _bracketSpan(openBracket)],
        collapsible: JsonCollapsibleInfo(
          path: path,
          childCount: childCount,
          isExpanded: true,
        ),
        hasActiveMatch: activeInKey,
      ));

      int nextLine = realLine + 1;

      // Children
      for (final child in children) {
        final result = _flatten(
          value: child.value,
          key: child.key,
          isLast: child.isLast,
          indent: indent + 1,
          path: child.childPath,
          query: query,
          matchOffset: currentOffset,
          realLine: nextLine,
          output: output,
        );
        currentOffset = result.matchOffset;
        nextLine = result.nextRealLine;
      }

      // Closing bracket
      output.add(JsonLine(
        indentLevel: indent,
        realLineNumber: nextLine,
        spans: [
          _bracketSpan(closeBracket),
          if (commaSpan != null) commaSpan,
        ],
      ));

      return (matchOffset: currentOffset, nextRealLine: nextLine + 1);
    } else {
      // Collapsed: "key": { … },
      //
      // The real line number is the opening bracket line. We advance
      // by the total expanded line count so the next sibling picks up
      // the correct real line number.
      final expandedLineCount = countExpandedLines(rawValue, lineCountMemo);

      output.add(JsonLine(
        indentLevel: indent,
        realLineNumber: realLine,
        spans: [
          ...keySpans,
          _bracketSpan(openBracket),
          TextSpan(
            text: ' … ',
            style: baseTextStyle.copyWith(
              color: InterceptlyTheme.textMuted,
              fontSize: 10,
            ),
          ),
          _bracketSpan(closeBracket),
          if (commaSpan != null) commaSpan,
        ],
        collapsible: JsonCollapsibleInfo(
          path: path,
          childCount: childCount,
          isExpanded: false,
        ),
        hasActiveMatch: activeInKey,
      ));

      // Advance the match offset past all collapsed children so
      // sibling nodes receive the correct offset.
      if (query != null) {
        currentOffset += matchCounts?[path] ?? 0;
      }

      return (
        matchOffset: currentOffset,
        nextRealLine: realLine + expandedLineCount,
      );
    }
  }
}

/// A child entry passed to [JsonLineFlattener._emitCollapsible] for iteration.
class _ChildEntry {
  final String? key;
  final dynamic value;
  final bool isLast;

  /// Path string for this child (e.g. `$.items[0]` or `$.data.name`).
  final String childPath;

  const _ChildEntry({
    this.key,
    required this.value,
    this.isLast = false,
    required this.childPath,
  });
}
