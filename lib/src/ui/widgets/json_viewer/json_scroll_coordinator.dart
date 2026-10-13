import 'package:flutter/widgets.dart';

import 'json_line.dart';
import 'json_viewer_style.dart';

/// Coordinates scrolling for the JSON viewer.
///
/// Responsibilities:
/// 1. Synchronizing vertical scroll positions between gutter and content.
/// 2. Animating both vertically and horizontally to the active search match.
/// 3. Retrying scrolling after layout settling when mounted offstage.
/// 4. Deduplicating scroll requests for the same query/index/trigger epoch.
class JsonScrollCoordinator {
  final ScrollController gutterScrollController = ScrollController();
  final ScrollController contentScrollController = ScrollController();
  final ScrollController horizontalScrollController = ScrollController();

  bool _isSyncingScroll = false;

  int? _lastScrolledGlobalIndex;
  String? _lastScrolledQuery;
  int? _lastScrollTrigger;

  /// Attaches synchronization listeners between the gutter and content controllers.
  void attach() {
    contentScrollController.addListener(_syncGutter);
    gutterScrollController.addListener(_syncContent);
  }

  /// Removes synchronization listeners and disposes all controllers.
  void dispose() {
    contentScrollController.removeListener(_syncGutter);
    gutterScrollController.removeListener(_syncContent);
    contentScrollController.dispose();
    gutterScrollController.dispose();
    horizontalScrollController.dispose();
  }

  void _syncGutter() {
    if (_isSyncingScroll) return;
    if (gutterScrollController.hasClients &&
        contentScrollController.hasClients) {
      if ((gutterScrollController.offset - contentScrollController.offset)
              .abs() >
          0.01) {
        _isSyncingScroll = true;
        gutterScrollController.jumpTo(contentScrollController.offset);
        _isSyncingScroll = false;
      }
    }
  }

  void _syncContent() {
    if (_isSyncingScroll) return;
    if (gutterScrollController.hasClients &&
        contentScrollController.hasClients) {
      if ((contentScrollController.offset - gutterScrollController.offset)
              .abs() >
          0.01) {
        _isSyncingScroll = true;
        contentScrollController.jumpTo(gutterScrollController.offset);
        _isSyncingScroll = false;
      }
    }
  }

  /// Resets the last scrolled state (e.g. when search query or active match changes).
  void resetLastScrolled({String? query}) {
    _lastScrolledGlobalIndex = null;
    _lastScrolledQuery = query;
  }

  /// Scrolls both vertically and horizontally to bring the active match on [line] into view.
  void scrollToActive({
    required int activeLineIndex,
    required JsonLine line,
    required double viewportHeight,
    required double viewportWidth,
    required double lineHeight,
    required TextStyle contentStyle,
    required int totalLineCount,
    required int? activeGlobalIndex,
    required String? searchQuery,
    required int? scrollTrigger,
    required bool Function() isMounted,
  }) {
    if (_lastScrolledGlobalIndex == activeGlobalIndex &&
        _lastScrolledQuery == searchQuery &&
        _lastScrollTrigger == scrollTrigger) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted()) return;
      if (contentScrollController.hasClients) {
        final maxScroll = contentScrollController.position.maxScrollExtent;
        final totalContentHeight = totalLineCount * lineHeight;
        final needsScroll = totalContentHeight > viewportHeight;
        if (needsScroll && maxScroll <= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (isMounted()) {
              scrollToActive(
                activeLineIndex: activeLineIndex,
                line: line,
                viewportHeight: viewportHeight,
                viewportWidth: viewportWidth,
                lineHeight: lineHeight,
                contentStyle: contentStyle,
                totalLineCount: totalLineCount,
                activeGlobalIndex: activeGlobalIndex,
                searchQuery: searchQuery,
                scrollTrigger: scrollTrigger,
                isMounted: isMounted,
              );
            }
          });
          return;
        }

        _lastScrolledGlobalIndex = activeGlobalIndex;
        _lastScrolledQuery = searchQuery;
        _lastScrollTrigger = scrollTrigger;

        if (maxScroll > 0) {
          final targetOffset =
              (activeLineIndex * lineHeight - (viewportHeight - lineHeight) / 2)
                  .clamp(0.0, maxScroll);
          if ((contentScrollController.offset - targetOffset).abs() > 1.0) {
            contentScrollController.animateTo(
              targetOffset,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
          }
        }

        if (horizontalScrollController.hasClients) {
          final maxHorizontal =
              horizontalScrollController.position.maxScrollExtent;
          if (maxHorizontal > 0) {
            final textBefore = line.spans
                .takeWhile((s) =>
                    s.style?.backgroundColor !=
                    JsonViewerColors.activeHighlight)
                .map((s) => s.text ?? '')
                .join();
            final textPainter = TextPainter(
              text: TextSpan(text: textBefore, style: contentStyle),
              textDirection: TextDirection.ltr,
            )..layout();
            final matchLeft = JsonViewerMetrics.contentLeftPadding +
                line.indentLevel * JsonViewerMetrics.indentWidth +
                textPainter.width;

            double matchWidth = 0.0;
            if (searchQuery != null && searchQuery.isNotEmpty) {
              final matchPainter = TextPainter(
                text: TextSpan(text: searchQuery, style: contentStyle),
                textDirection: TextDirection.ltr,
              )..layout();
              matchWidth = matchPainter.width;
            }

            final targetHorizontal =
                (matchLeft - (viewportWidth - matchWidth) / 2)
                    .clamp(0.0, maxHorizontal);

            if ((horizontalScrollController.offset - targetHorizontal).abs() >
                1.0) {
              horizontalScrollController.animateTo(
                targetHorizontal,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
              );
            }
          }
        }
      }
    });
  }
}
