import 'package:flutter/painting.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

/// Syntax and search-highlight colors used by the JSON viewer.
///
/// [activeHighlight] doubles as the marker that identifies the currently
/// active search match inside a [TextSpan] tree (see
/// `JsonSearch.spanHasActiveHighlight`), so it must stay the single source
/// of truth for that color.
abstract final class JsonViewerColors {
  static const Color key = InterceptlyGlobalColor.blue400;
  static const Color string = InterceptlyGlobalColor.red400;
  static const Color number = InterceptlyGlobalColor.green400;
  static const Color boolean = InterceptlyGlobalColor.blue500;
  static const Color nullValue = InterceptlyGlobalColor.blue500;
  static const Color punctuation = InterceptlyGlobalColor.textQuaternary;
  static const Color highlight = InterceptlyGlobalColor.highlightStrong;
  static const Color activeHighlight = InterceptlyGlobalColor.orange;
  static const Color lineNumber = InterceptlyGlobalColor.textMuted;
}

/// Layout constants and thresholds for the JSON viewer.
abstract final class JsonViewerMetrics {
  /// Height of one rendered line (fontSize 12 × height 1.5).
  static const double lineHeight = 18.0;

  /// Horizontal indentation per nesting level.
  static const double indentWidth = 16.0;

  /// Width of the fold/unfold arrow slot in the gutter.
  static const double foldIconWidth = 16.0;

  /// Left padding applied to the content column.
  static const double contentLeftPadding = 4.0;

  /// Documents whose fully-expanded line count exceeds this are collapsed
  /// to the root level by default.
  static const int largeDocLineThreshold = 1500;

  /// Nodes with more direct children than this start collapsed.
  static const int defaultExpandChildLimit = 20;
}
