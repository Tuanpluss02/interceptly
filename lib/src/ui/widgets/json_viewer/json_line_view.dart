import 'package:flutter/widgets.dart';

import 'json_line.dart';
import 'json_viewer_style.dart';

/// Renders the content of a single JSON line without line wrapping.
class JsonLineView extends StatelessWidget {
  final JsonLine line;
  final double lineHeight;
  final TextStyle style;

  const JsonLineView({
    super.key,
    required this.line,
    required this.lineHeight,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: lineHeight,
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.only(
        left: line.indentLevel * JsonViewerMetrics.indentWidth,
      ),
      child: Text.rich(
        TextSpan(
          style: style,
          children: line.spans,
        ),
        softWrap: false,
        overflow: TextOverflow.visible,
      ),
    );
  }
}
