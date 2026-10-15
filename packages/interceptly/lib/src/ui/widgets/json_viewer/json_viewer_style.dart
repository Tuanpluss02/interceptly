import 'package:flutter/widgets.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

/// Resolved syntax highlighting colors for the JSON viewer.
class JsonViewerColorsData {
  const JsonViewerColorsData({
    required this.key,
    required this.string,
    required this.number,
    required this.boolean,
    required this.nullValue,
    required this.punctuation,
    required this.highlight,
    required this.activeHighlight,
    required this.lineNumber,
  });

  final Color key;
  final Color string;
  final Color number;
  final Color boolean;
  final Color nullValue;
  final Color punctuation;
  final Color highlight;
  final Color activeHighlight;
  final Color lineNumber;
}

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

  /// Resolves syntax highlighting colors appropriate for [brightness].
  static JsonViewerColorsData of(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const JsonViewerColorsData(
        key: InterceptlyGlobalColor.blue400,
        string: InterceptlyGlobalColor.red400,
        number: InterceptlyGlobalColor.green400,
        boolean: InterceptlyGlobalColor.blue500,
        nullValue: InterceptlyGlobalColor.blue500,
        punctuation: InterceptlyGlobalColor.textQuaternary,
        highlight: InterceptlyGlobalColor.highlightStrong,
        activeHighlight: InterceptlyGlobalColor.orange,
        lineNumber: InterceptlyGlobalColor.textMuted,
      );
    }
    return const JsonViewerColorsData(
      key: InterceptlyGlobalColor.blue500,
      string: InterceptlyGlobalColor.red500,
      number: InterceptlyGlobalColor.green500,
      boolean: InterceptlyGlobalColor.indigo500,
      nullValue: InterceptlyGlobalColor.indigo500,
      punctuation: InterceptlyGlobalColor.textTertiaryLight,
      highlight: InterceptlyGlobalColor.highlightSoft,
      activeHighlight: InterceptlyGlobalColor.orange,
      lineNumber: InterceptlyGlobalColor.textTertiaryLight,
    );
  }
}

/// Layout constants and thresholds for the JSON viewer.
abstract final class JsonViewerMetrics {
  /// Height of one rendered line (fontSize 12 × height 1.5).
  static const double lineHeight = 18.0;

  /// Height of one rendered line scaled by [MediaQuery.textScalerOf].
  static double lineHeightOf(BuildContext context) {
    return MediaQuery.textScalerOf(context).scale(lineHeight);
  }

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
