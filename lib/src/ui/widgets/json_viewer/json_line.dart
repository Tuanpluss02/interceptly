import 'package:flutter/painting.dart';

/// A single visual line in the flattened JSON view.
class JsonLine {
  /// Indentation depth (0 = root).
  final int indentLevel;

  /// Line number in the **fully-expanded** document.
  ///
  /// When collapsible regions are folded, visible line numbers will
  /// skip the hidden range — matching VSCode behavior.
  final int realLineNumber;

  /// Inline spans forming the visible text content of this line.
  final List<TextSpan> spans;

  /// Non-null when this line opens a collapsible block.
  final JsonCollapsibleInfo? collapsible;

  /// `true` when this line contains the currently active search match.
  final bool hasActiveMatch;

  const JsonLine({
    required this.indentLevel,
    required this.realLineNumber,
    required this.spans,
    this.collapsible,
    this.hasActiveMatch = false,
  });

  /// Approximate rendered character count (used to size the scroll width).
  int get approximateLength {
    var len = indentLevel * 2;
    for (final s in spans) {
      len += s.text?.length ?? 0;
    }
    return len;
  }
}

/// Metadata attached to a collapsible header line.
class JsonCollapsibleInfo {
  /// Unique path identifying this node (e.g. `$.data.items[0]`).
  final String path;

  /// Number of direct children (used for the default expand heuristic).
  final int childCount;

  /// Snapshot of the expanded state at build time.
  final bool isExpanded;

  const JsonCollapsibleInfo({
    required this.path,
    required this.childCount,
    required this.isExpanded,
  });
}
