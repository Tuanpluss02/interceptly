import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

import '../toast_notification.dart';
import 'json_expansion_state.dart';
import 'json_line.dart';
import 'json_line_flattener.dart';
import 'json_search.dart';
import 'json_viewer_style.dart';

export 'json_expansion_state.dart';
export 'json_line.dart';
export 'json_line_flattener.dart';
export 'json_search.dart';
export 'json_viewer_style.dart';

/// Collapsible JSON renderer with VSCode-style line numbers, gutter
/// expand/collapse, search highlighting, and copy support.
///
/// Line numbers reflect the position in the **fully-expanded** document.
/// Collapsed regions cause line numbers to skip, matching VSCode behavior.
class JsonViewer extends StatefulWidget {
  /// JSON-like data (Map/List/scalars/String) to render.
  final dynamic data;

  /// Optional search term to highlight in rendered nodes.
  final String? searchQuery;

  /// Global match index offset for coordinated tab search navigation.
  final int matchOffset;

  /// Active global match index currently selected by parent UI.
  final int? activeGlobalIndex;

  /// Epoch/generation counter to explicitly re-trigger scrolling to the active match
  /// (e.g. when pressing goto / Next / Prev match or switching back across tabs).
  final int? scrollTrigger;

  /// Optional flag to control scrollbar thumb visibility.
  /// If null, follows standard platform behavior (shows while scrolling or hovering).
  final bool? thumbVisibility;

  /// Creates a JSON viewer for [data] with optional search metadata.
  const JsonViewer({
    super.key,
    required this.data,
    this.searchQuery,
    this.matchOffset = 0,
    this.activeGlobalIndex,
    this.scrollTrigger,
    this.thumbVisibility,
  });

  /// Format any data into a pretty-printed JSON string.
  ///
  /// Delegates to [JsonSearch.formatData].
  static String formatData(dynamic data) => JsonSearch.formatData(data);

  /// Counts case-insensitive query matches within structured JSON data.
  ///
  /// Delegates to [JsonSearch.countMatches].
  static int countMatches(dynamic data, String query) =>
      JsonSearch.countMatches(data, query);

  /// Build highlighted [TextSpan] list for [text], marking query matches.
  ///
  /// Delegates to [JsonSearch.buildHighlightedSpans].
  static List<TextSpan> buildHighlightedSpans(
    String text,
    String lowerQuery,
    int matchOffset,
    int? activeGlobalIndex,
    Color baseColor,
  ) =>
      JsonSearch.buildHighlightedSpans(
        text,
        lowerQuery,
        matchOffset,
        activeGlobalIndex,
        baseColor,
      );

  @override
  State<JsonViewer> createState() => _JsonViewerState();
}

// ─────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────

class _JsonViewerState extends State<JsonViewer> {
  final JsonExpansionState _expansion = JsonExpansionState();

  final ScrollController _gutterScrollController = ScrollController();

  final ScrollController _contentScrollController = ScrollController();

  final ScrollController _horizontalScrollController = ScrollController();

  bool _isSyncingScroll = false;

  List<JsonLine>? _memoLines;

  double _memoLineNumberWidth = 0;

  int _memoMaxChars = 0;

  Map<String, int>? _memoMatchCounts;

  Object? _memoData;

  String? _memoQuery;

  int _memoMatchOffset = 0;

  int? _memoActiveGlobalIndex;

  Brightness? _memoBrightness;

  Expando<int>? _lineCountMemo;

  final FocusNode _selectableFocusNode = FocusNode();

  final GlobalKey _contentViewportKey = GlobalKey();

  late final _JsonViewerSelectionContainerDelegate _selectionContainerDelegate =
      _JsonViewerSelectionContainerDelegate(
    horizontalController: _horizontalScrollController,
    viewportKey: _contentViewportKey,
  );

  @visibleForTesting
  List<JsonLine>? get memoLinesForTest => _memoLines;

  @visibleForTesting
  ScrollController get contentScrollControllerForTest =>
      _contentScrollController;

  @visibleForTesting
  ScrollController get horizontalScrollControllerForTest =>
      _horizontalScrollController;

  int? _lastScrolledGlobalIndex;
  String? _lastScrolledQuery;
  int? _lastScrollTrigger;

  void _checkScrollToActive({
    required int activeLineIndex,
    required JsonLine line,
    required double viewportHeight,
    required double viewportWidth,
    required double lineHeight,
    required TextStyle contentStyle,
  }) {
    if (_lastScrolledGlobalIndex == widget.activeGlobalIndex &&
        _lastScrolledQuery == widget.searchQuery &&
        _lastScrollTrigger == widget.scrollTrigger) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_contentScrollController.hasClients) {
        final maxScroll = _contentScrollController.position.maxScrollExtent;
        final totalContentHeight = (_memoLines?.length ?? 0) * lineHeight;
        final needsScroll = totalContentHeight > viewportHeight;
        if (needsScroll && maxScroll <= 0) {
          // Layout extent not yet settled (e.g. just mounted from offstage)
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _checkScrollToActive(
                activeLineIndex: activeLineIndex,
                line: line,
                viewportHeight: viewportHeight,
                viewportWidth: viewportWidth,
                lineHeight: lineHeight,
                contentStyle: contentStyle,
              );
            }
          });
          return;
        }

        _lastScrolledGlobalIndex = widget.activeGlobalIndex;
        _lastScrolledQuery = widget.searchQuery;
        _lastScrollTrigger = widget.scrollTrigger;

        if (maxScroll > 0) {
          final targetOffset =
              (activeLineIndex * lineHeight - (viewportHeight - lineHeight) / 2)
                  .clamp(0.0, maxScroll);
          if ((_contentScrollController.offset - targetOffset).abs() > 1.0) {
            _contentScrollController.animateTo(
              targetOffset,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
          }
        }

        if (_horizontalScrollController.hasClients) {
          final maxHorizontal =
              _horizontalScrollController.position.maxScrollExtent;
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
            final matchLeft = 4.0 + line.indentLevel * 16.0 + textPainter.width;

            double matchWidth = 0.0;
            if (widget.searchQuery != null && widget.searchQuery!.isNotEmpty) {
              final matchPainter = TextPainter(
                text: TextSpan(text: widget.searchQuery!, style: contentStyle),
                textDirection: TextDirection.ltr,
              )..layout();
              matchWidth = matchPainter.width;
            }

            final targetHorizontal =
                (matchLeft - (viewportWidth - matchWidth) / 2)
                    .clamp(0.0, maxHorizontal);

            if ((_horizontalScrollController.offset - targetHorizontal).abs() >
                1.0) {
              _horizontalScrollController.animateTo(
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

  @override
  void initState() {
    super.initState();
    _contentScrollController.addListener(_syncGutter);
    _gutterScrollController.addListener(_syncContent);
  }

  void _syncGutter() {
    if (_isSyncingScroll) return;
    if (_gutterScrollController.hasClients &&
        _contentScrollController.hasClients) {
      if ((_gutterScrollController.offset - _contentScrollController.offset)
              .abs() >
          0.01) {
        _isSyncingScroll = true;
        _gutterScrollController.jumpTo(_contentScrollController.offset);
        _isSyncingScroll = false;
      }
    }
  }

  void _syncContent() {
    if (_isSyncingScroll) return;
    if (_gutterScrollController.hasClients &&
        _contentScrollController.hasClients) {
      if ((_contentScrollController.offset - _gutterScrollController.offset)
              .abs() >
          0.01) {
        _isSyncingScroll = true;
        _contentScrollController.jumpTo(_gutterScrollController.offset);
        _isSyncingScroll = false;
      }
    }
  }

  @override
  void didUpdateWidget(covariant JsonViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeGlobalIndex != oldWidget.activeGlobalIndex ||
        widget.searchQuery != oldWidget.searchQuery) {
      _expansion.resetSearch();
      _lastScrolledGlobalIndex = null;
      _lastScrolledQuery = widget.searchQuery;
    }
    if (!identical(widget.data, oldWidget.data)) {
      _lineCountMemo = null;
      _expansion.clear();
    }
    if (!identical(widget.data, oldWidget.data) ||
        widget.searchQuery != oldWidget.searchQuery ||
        widget.matchOffset != oldWidget.matchOffset ||
        widget.activeGlobalIndex != oldWidget.activeGlobalIndex) {
      _memoLines = null;
    }
  }

  @override
  void dispose() {
    _contentScrollController.removeListener(_syncGutter);
    _gutterScrollController.removeListener(_syncContent);
    _contentScrollController.dispose();
    _gutterScrollController.dispose();
    _horizontalScrollController.dispose();
    _selectableFocusNode.dispose();
    _selectionContainerDelegate.dispose();
    super.dispose();
  }

  void _toggleNode(String path, int childCount) {
    setState(() {
      _expansion.toggle(path, childCount);
      _memoLines = null;
    });
  }

  void _ensureLines() {
    final query = widget.searchQuery?.toLowerCase().trim();
    final effectiveQuery = (query != null && query.isNotEmpty) ? query : null;
    final brightness = InterceptlyTheme.brightness;
    if (_memoLines != null &&
        identical(_memoData, widget.data) &&
        _memoQuery == effectiveQuery &&
        _memoMatchOffset == widget.matchOffset &&
        _memoActiveGlobalIndex == widget.activeGlobalIndex &&
        _memoBrightness == brightness) {
      return;
    }
    _lineCountMemo ??= Expando<int>('json_line_counts');
    _expansion.forceCollapse = JsonLineFlattener.countExpandedLines(
          widget.data,
          _lineCountMemo,
        ) >
        JsonViewerMetrics.largeDocLineThreshold;
    _memoMatchCounts = effectiveQuery == null
        ? null
        : JsonSearch.matchCountsByPath(widget.data, effectiveQuery);

    final flattener = JsonLineFlattener(
      expansion: _expansion,
      activeGlobalIndex: widget.activeGlobalIndex,
      matchCounts: _memoMatchCounts,
      lineCountMemo: _lineCountMemo,
      baseTextStyle: _baseTextStyle,
    );

    final lines = flattener.flatten(
      widget.data,
      query: effectiveQuery,
      matchOffset: widget.matchOffset,
    );

    _memoLines = lines;
    _memoData = widget.data;
    _memoQuery = effectiveQuery;
    _memoMatchOffset = widget.matchOffset;
    _memoActiveGlobalIndex = widget.activeGlobalIndex;
    _memoBrightness = brightness;
    if (lines.isEmpty) {
      _memoLineNumberWidth = 0;
      _memoMaxChars = 0;
    } else {
      final digits = lines.last.realLineNumber.toString().length;
      _memoLineNumberWidth = digits * 8.0 + 8.0;
      int maxLen = 60;
      final sampleCount = math.min(lines.length, 200);
      for (int i = 0; i < sampleCount; i++) {
        final line = lines[i];
        var len = line.indentLevel * 2;
        for (final s in line.spans) {
          len += (s.text?.length ?? 0);
        }
        if (len > maxLen) maxLen = len;
      }
      _memoMaxChars = maxLen;
    }
  }

  void _copyToClipboard() {
    final formatted = JsonViewer.formatData(widget.data);
    Clipboard.setData(ClipboardData(text: formatted)).then((_) {
      if (mounted) {
        ToastNotification.show('Copied to clipboard', contextHint: context);
      }
    });
  }

  TextStyle get _baseTextStyle => InterceptlyTheme.typography.bodyMediumRegular;

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.data == null) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          'No Data',
          style: _baseTextStyle.copyWith(
            fontStyle: FontStyle.italic,
            color: InterceptlyTheme.textMuted,
          ),
        ),
      );
    }

    _ensureLines();
    final lines = _memoLines!;
    if (lines.isEmpty) return const SizedBox.shrink();

    final lineNumberWidth = _memoLineNumberWidth;

    final contentStyle = _baseTextStyle.copyWith(
      fontFamilyFallback: const ['monospace'],
      fontSize: 12,
      height: 1.5,
    );
    const lineHeight = 18.0; // fontSize 12 × height 1.5

    final maxChars = _memoMaxChars;
    int? activeLineIndex;
    if (widget.activeGlobalIndex != null) {
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].hasActiveMatch) {
          activeLineIndex = i;
          break;
        }
      }
    }

    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : (lines.length * lineHeight).clamp(24.0, 500.0);

          final gutterTotalWidth =
              lineNumberWidth + JsonViewerMetrics.foldIconWidth + 8.0;
          final minContentWidth = constraints.hasBoundedWidth
              ? math.max(0.0, constraints.maxWidth - gutterTotalWidth)
              : 0.0;
          final contentWidth = math.max(minContentWidth, maxChars * 8.5 + 60.0);

          if (activeLineIndex != null) {
            _checkScrollToActive(
              activeLineIndex: activeLineIndex,
              line: lines[activeLineIndex],
              viewportHeight: viewportHeight,
              viewportWidth: minContentWidth,
              lineHeight: lineHeight,
              contentStyle: contentStyle,
            );
          }

          return SizedBox(
            height: viewportHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                DefaultTextStyle(
                  style: contentStyle,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: gutterTotalWidth,
                        height: viewportHeight,
                        child: Container(
                          padding: const EdgeInsets.only(right: 4.0),
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: InterceptlyTheme.dividerSubtle,
                                width: 1.0,
                              ),
                            ),
                          ),
                          child: ListView.builder(
                            controller: _gutterScrollController,
                            itemExtent: lineHeight,
                            itemCount: lines.length,
                            addAutomaticKeepAlives: false,
                            physics: const ClampingScrollPhysics(),
                            itemBuilder: (context, index) {
                              return _buildGutterCell(
                                line: lines[index],
                                lineNumberWidth: lineNumberWidth,
                                lineHeight: lineHeight,
                                style: contentStyle,
                              );
                            },
                          ),
                        ),
                      ),
                      Expanded(
                        child: ScrollbarTheme(
                          data: ScrollbarThemeData(
                            thumbColor:
                                WidgetStateProperty.resolveWith((states) {
                              final baseColor =
                                  InterceptlyTheme.colors.textTertiary;
                              if (states.contains(WidgetState.dragged)) {
                                return baseColor.withValues(alpha: 0.6);
                              }
                              if (states.contains(WidgetState.hovered)) {
                                return baseColor.withValues(alpha: 0.5);
                              }
                              return baseColor.withValues(alpha: 0.35);
                            }),
                            radius: const Radius.circular(4.0),
                            thickness: const WidgetStatePropertyAll(5.0),
                            crossAxisMargin: 0.0,
                            mainAxisMargin: 0.0,
                            interactive: true,
                          ),
                          child: Scrollbar(
                            controller: _contentScrollController,
                            notificationPredicate: (notif) =>
                                notif.metrics.axis == Axis.vertical,
                            interactive: true,
                            thumbVisibility: widget.thumbVisibility,
                            child: Scrollbar(
                              controller: _horizontalScrollController,
                              notificationPredicate: (notif) =>
                                  notif.metrics.axis == Axis.horizontal,
                              interactive: true,
                              thumbVisibility: widget.thumbVisibility,
                              child: KeyedSubtree(
                                key: _contentViewportKey,
                                child: SelectableRegion(
                                  focusNode: _selectableFocusNode,
                                  selectionControls:
                                      materialTextSelectionControls,
                                  child: SelectionContainer(
                                    delegate: _selectionContainerDelegate,
                                    child: SelectionContainer.disabled(
                                      child: SingleChildScrollView(
                                        controller: _horizontalScrollController,
                                        scrollDirection: Axis.horizontal,
                                        child: SizedBox(
                                          width: contentWidth,
                                          height: viewportHeight,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                                left: 4.0),
                                            child: ListView.builder(
                                              controller:
                                                  _contentScrollController,
                                              itemExtent: lineHeight,
                                              itemCount: lines.length,
                                              addAutomaticKeepAlives: false,
                                              physics:
                                                  const ClampingScrollPhysics(),
                                              itemBuilder: (context, index) {
                                                final lineWidget = _buildLine(
                                                  index,
                                                  lines[index],
                                                  lineHeight,
                                                  contentStyle,
                                                );
                                                return SelectionRegistrarScope(
                                                  registrar:
                                                      _selectionContainerDelegate,
                                                  child: lineWidget,
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: -10,
                  right: -10,
                  child: Material(
                    color: InterceptlyGlobalColor.transparent,
                    child: IconButton(
                      icon: const Icon(
                        Icons.copy,
                        size: 16,
                        color: InterceptlyTheme.textMuted,
                      ),
                      tooltip: 'Copy JSON',
                      onPressed: _copyToClipboard,
                      splashRadius: 16,
                      constraints: const BoxConstraints.tightFor(
                        width: 24,
                        height: 24,
                      ),
                      padding: EdgeInsets.zero,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLine(
    int index,
    JsonLine line,
    double lineHeight,
    TextStyle style,
  ) {
    return Container(
      height: lineHeight,
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.only(left: line.indentLevel * 16.0),
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

  // ─────────────────────────────────────────────────────────────
  // Gutter & Content line builders
  // ─────────────────────────────────────────────────────────────

  /// Builds one gutter row: **real line number** + optional **fold icon**.
  ///
  /// The entire row is tappable for collapsible lines so the touch
  /// target is wide enough on mobile.
  Widget _buildGutterCell({
    required JsonLine line,
    required double lineNumberWidth,
    required double lineHeight,
    required TextStyle style,
  }) {
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
        onTap: () => _toggleNode(
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

/// A selection container delegate that provides horizontal auto-scrolling
/// while selecting text across wide JSON lines, without crashing on empty space.
class _JsonViewerSelectionContainerDelegate
    extends StaticSelectionContainerDelegate {
  _JsonViewerSelectionContainerDelegate({
    required this.horizontalController,
    required this.viewportKey,
  });

  final ScrollController horizontalController;
  final GlobalKey viewportKey;

  static const double _edgeMargin = 40.0;

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
