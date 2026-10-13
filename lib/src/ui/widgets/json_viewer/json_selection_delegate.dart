import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A selection container delegate that provides horizontal auto-scrolling
/// while selecting text across wide JSON lines, without crashing on empty space.
class JsonViewerSelectionDelegate extends StaticSelectionContainerDelegate {
  final ScrollController horizontalController;
  final GlobalKey viewportKey;

  static const double _edgeMargin = 40.0;

  JsonViewerSelectionDelegate({
    required this.horizontalController,
    required this.viewportKey,
  });

  @override
  SelectionResult handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent event) {
    final result = super.handleSelectionEdgeUpdate(event);

    final renderObject = viewportKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return result;
    }

    if (!horizontalController.hasClients) {
      return result;
    }

    final localPos = renderObject.globalToLocal(event.globalPosition);
    final viewportWidth = renderObject.size.width;

    double delta = 0.0;
    if (localPos.dx > viewportWidth - _edgeMargin) {
      // Near or past right edge -> scroll right
      final overscroll =
          math.max(1.0, localPos.dx - (viewportWidth - _edgeMargin));
      delta = (overscroll * 0.4).clamp(4.0, 24.0);
    } else if (localPos.dx < _edgeMargin) {
      // Near or past left edge -> scroll left
      final overscroll = math.max(1.0, _edgeMargin - localPos.dx);
      delta = -(overscroll * 0.4).clamp(4.0, 24.0);
    }

    if (delta != 0.0) {
      final currentOffset = horizontalController.offset;
      final maxScroll = horizontalController.position.maxScrollExtent;
      final targetOffset = (currentOffset + delta).clamp(0.0, maxScroll);
      if ((targetOffset - currentOffset).abs() > 0.01) {
        horizontalController.jumpTo(targetOffset);
        return SelectionResult.pending;
      }
    }

    return result;
  }
}
