import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

import 'json_line.dart';
import 'json_viewer_style.dart';

/// Builds one gutter cell: the **real line number** in the fully-expanded document
/// and an optional **fold icon** for collapsible regions.
///
/// The entire cell is tappable for collapsible lines so mobile touch targets remain comfortable.
class JsonGutterCell extends StatelessWidget {
  final JsonLine line;
  final double lineNumberWidth;
  final double lineHeight;
  final TextStyle style;
  final void Function(String path, int childCount) onToggle;

  const JsonGutterCell({
    super.key,
    required this.line,
    required this.lineNumberWidth,
    required this.lineHeight,
    required this.style,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final hasFold = line.collapsible != null;

    Widget cell = SizedBox(
      height: lineHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: lineNumberWidth,
              child: Text(
                '${line.realLineNumber}',
                textAlign: TextAlign.right,
                style: style.copyWith(color: JsonViewerColors.lineNumber),
              ),
            ),
            SizedBox(
              width: JsonViewerMetrics.foldIconWidth,
              height: lineHeight,
              child: hasFold
                  ? Center(
                      child: Transform.rotate(
                        angle: line.collapsible!.isExpanded ? 0 : -1.5708,
                        child: const Icon(
                          Icons.arrow_drop_down,
                          size: 16,
                          color: InterceptlyTheme.textMuted,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );

    if (hasFold) {
      cell = GestureDetector(
        onTap: () => onToggle(
          line.collapsible!.path,
          line.collapsible!.childCount,
        ),
        behavior: HitTestBehavior.opaque,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: cell,
        ),
      );
    }

    return cell;
  }
}
