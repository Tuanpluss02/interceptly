import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

import '../toast_notification.dart';
import 'json_expansion_state.dart';
import 'json_gutter.dart';
import 'json_line.dart';
import 'json_line_flattener.dart';
import 'json_line_view.dart';
import 'json_scroll_coordinator.dart';
import 'json_search.dart';
import 'json_selection_delegate.dart';
import 'json_viewer_style.dart';

export 'json_expansion_state.dart';
export 'json_gutter.dart';
export 'json_line.dart';
export 'json_line_flattener.dart';
export 'json_line_view.dart';
export 'json_scroll_coordinator.dart';
export 'json_search.dart';
export 'json_selection_delegate.dart';
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

class _JsonViewerState extends State<JsonViewer> {
  final JsonExpansionState _expansion = JsonExpansionState();
  late final JsonScrollCoordinator _scroll = JsonScrollCoordinator();

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

  late final JsonViewerSelectionDelegate _selectionContainerDelegate =
      JsonViewerSelectionDelegate(
    horizontalController: _scroll.horizontalScrollController,
    viewportKey: _contentViewportKey,
  );

  @visibleForTesting
  List<JsonLine>? get memoLinesForTest => _memoLines;

  @visibleForTesting
  ScrollController get contentScrollControllerForTest =>
      _scroll.contentScrollController;

  @visibleForTesting
  ScrollController get horizontalScrollControllerForTest =>
      _scroll.horizontalScrollController;

  @override
  void initState() {
    super.initState();
    _scroll.attach();
  }

  @override
  void didUpdateWidget(covariant JsonViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeGlobalIndex != oldWidget.activeGlobalIndex ||
        widget.searchQuery != oldWidget.searchQuery) {
      _expansion.resetSearch();
      _scroll.resetLastScrolled(query: widget.searchQuery);
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
    _scroll.dispose();
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
    const lineHeight = 18.0;

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
            _scroll.scrollToActive(
              activeLineIndex: activeLineIndex,
              line: lines[activeLineIndex],
              viewportHeight: viewportHeight,
              viewportWidth: minContentWidth,
              lineHeight: lineHeight,
              contentStyle: contentStyle,
              totalLineCount: lines.length,
              activeGlobalIndex: widget.activeGlobalIndex,
              searchQuery: widget.searchQuery,
              scrollTrigger: widget.scrollTrigger,
              isMounted: () => mounted,
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
                            controller: _scroll.gutterScrollController,
                            itemExtent: lineHeight,
                            itemCount: lines.length,
                            addAutomaticKeepAlives: false,
                            physics: const ClampingScrollPhysics(),
                            itemBuilder: (context, index) {
                              return JsonGutterCell(
                                line: lines[index],
                                lineNumberWidth: lineNumberWidth,
                                lineHeight: lineHeight,
                                style: contentStyle,
                                onToggle: _toggleNode,
                              );
                            },
                          ),
                        ),
                      ),
                      _buildContent(
                        lines: lines,
                        lineHeight: lineHeight,
                        contentStyle: contentStyle,
                        contentWidth: contentWidth,
                        viewportHeight: viewportHeight,
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

  Widget _buildContent({
    required List<JsonLine> lines,
    required double lineHeight,
    required TextStyle contentStyle,
    required double contentWidth,
    required double viewportHeight,
  }) {
    return Expanded(
      child: ScrollbarTheme(
        data: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            final baseColor = InterceptlyTheme.colors.textTertiary;
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
          controller: _scroll.contentScrollController,
          notificationPredicate: (notif) => notif.metrics.axis == Axis.vertical,
          interactive: true,
          thumbVisibility: widget.thumbVisibility,
          child: Scrollbar(
            controller: _scroll.horizontalScrollController,
            notificationPredicate: (notif) =>
                notif.metrics.axis == Axis.horizontal,
            interactive: true,
            thumbVisibility: widget.thumbVisibility,
            child: KeyedSubtree(
              key: _contentViewportKey,
              child: SelectableRegion(
                focusNode: _selectableFocusNode,
                selectionControls: materialTextSelectionControls,
                child: SelectionContainer(
                  delegate: _selectionContainerDelegate,
                  child: SelectionContainer.disabled(
                    child: SingleChildScrollView(
                      controller: _scroll.horizontalScrollController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: contentWidth,
                        height: viewportHeight,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4.0),
                          child: ListView.builder(
                            controller: _scroll.contentScrollController,
                            itemExtent: lineHeight,
                            itemCount: lines.length,
                            addAutomaticKeepAlives: false,
                            physics: const ClampingScrollPhysics(),
                            itemBuilder: (context, index) {
                              final lineWidget = JsonLineView(
                                line: lines[index],
                                lineHeight: lineHeight,
                                style: contentStyle,
                              );
                              return SelectionRegistrarScope(
                                registrar: _selectionContainerDelegate,
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
    );
  }
}
