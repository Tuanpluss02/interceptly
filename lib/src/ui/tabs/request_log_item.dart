import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

import '../../model/search_match_scope.dart';

/// Visual treatment for the status pill on list rows (so 2xx reads
/// differently from HTTP method chips at a glance).
class _ListStatusLook {
  const _ListStatusLook({
    required this.background,
    required this.foreground,
    this.border,
  });

  final Color background;
  final Color foreground;
  final Color? border;

  static _ListStatusLook forRow({
    required int status,
    required bool isPending,
    required bool isErrorWithoutStatus,
    required InterceptlyColors palette,
  }) {
    if (isPending) {
      final s = InterceptlyTheme.getStatusStyle(status);
      return _ListStatusLook(
        background: palette.surfaceTertiary,
        foreground: s.text,
      );
    }
    if (isErrorWithoutStatus) {
      return const _ListStatusLook(
        background: InterceptlyTheme.red500,
        foreground: InterceptlyGlobalColor.white,
      );
    }
    if (status >= 200 && status < 300) {
      return _ListStatusLook(
        background: InterceptlyTheme.green500.withValues(alpha: 0.14),
        foreground: InterceptlyTheme.green400,
        border: InterceptlyTheme.green500.withValues(alpha: 0.38),
      );
    }
    if (status >= 400 && status < 500) {
      return const _ListStatusLook(
        background: InterceptlyTheme.yellow500,
        foreground: InterceptlyGlobalColor.black,
      );
    }
    if (status >= 500) {
      return const _ListStatusLook(
        background: InterceptlyTheme.red500,
        foreground: InterceptlyGlobalColor.white,
      );
    }
    if (status == 101) {
      return const _ListStatusLook(
        background: InterceptlyTheme.purple500,
        foreground: InterceptlyGlobalColor.white,
      );
    }
    final s = InterceptlyTheme.getStatusStyle(status);
    return _ListStatusLook(background: s.bg, foreground: s.text);
  }
}

class RequestLogItem extends StatelessWidget {
  const RequestLogItem({
    super.key,
    required this.method,
    required this.url,
    required this.time,
    required this.duration,
    required this.status,
    required this.hasError,
    required this.isPending,
    required this.responseSizeBytes,
    required this.onTap,
    required this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.searchScopes,
    this.highlightQuery,
  });

  final String method;
  final String url;
  final String time;
  final String duration;
  final int status;
  final bool hasError;
  final bool isPending;
  final int responseSizeBytes;
  final bool isSelectionMode;
  final bool isSelected;
  final Set<SearchMatchScope>? searchScopes;
  final String? highlightQuery;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static TextSpan _buildHighlightedSpan({
    required String text,
    required String? query,
    required TextStyle normalStyle,
    required TextStyle highlightStyle,
  }) {
    final q = query?.trim().toLowerCase();
    if (q == null || q.isEmpty) {
      return TextSpan(text: text, style: normalStyle);
    }
    final lowerText = text.toLowerCase();
    int start = 0;
    int index = lowerText.indexOf(q, start);
    if (index == -1) {
      return TextSpan(text: text, style: normalStyle);
    }

    final spans = <InlineSpan>[];
    while (index != -1) {
      if (index > start) {
        spans.add(TextSpan(
          text: text.substring(start, index),
          style: normalStyle,
        ));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + q.length),
        style: highlightStyle,
      ));
      start = index + q.length;
      index = lowerText.indexOf(q, start);
    }
    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: normalStyle,
      ));
    }
    return TextSpan(children: spans);
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _buildMetaLine() {
    final hasSize = !isPending && !(status == 0 && hasError);
    if (hasSize) {
      return '$time · $duration · ${_formatBytes(responseSizeBytes)}';
    }
    return '$time · $duration';
  }

  static ({String path, String host}) _splitUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasAuthority) {
      final pathWithQuery =
          uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
      final path = pathWithQuery.isEmpty ? '/' : pathWithQuery;
      return (path: path, host: uri.host);
    }
    return (path: url, host: '');
  }

  @override
  Widget build(BuildContext context) {
    final colors = InterceptlyTheme.colors;
    final mStyle = InterceptlyTheme.getMethodStyle(method);
    final isErrorWithoutStatus = status == 0 && hasError;
    final statusLook = _ListStatusLook.forRow(
      status: status,
      isPending: isPending,
      isErrorWithoutStatus: isErrorWithoutStatus,
      palette: colors,
    );

    final (:path, :host) = _splitUrl(url);
    final borderRadius = BorderRadius.circular(InterceptlyTheme.radius.lg);
    final metaColor = colors.textTertiary;

    return Material(
      color: isSelected
          ? colors.actionPrimary.withValues(alpha: 0.12)
          : colors.surfaceSecondary,
      elevation: 0,
      shadowColor: InterceptlyGlobalColor.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(
          color: isSelected
              ? colors.actionPrimary.withValues(alpha: 0.45)
              : InterceptlyTheme.dividerSubtle,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: borderRadius,
        hoverColor: InterceptlyTheme.hoverOverlay,
        splashColor: colors.actionPrimary.withValues(alpha: 0.10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 14.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isSelectionMode) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _SelectionCheckbox(
                    isSelected: isSelected,
                    actionColor: colors.actionPrimary,
                    onTap: onTap,
                  ),
                ),
                const SizedBox(width: 12),
              ],

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: mStyle.bg.withValues(alpha: 0.28),
                  border: Border.all(
                    color: mStyle.border.withValues(alpha: 0.85),
                  ),
                  borderRadius: BorderRadius.circular(
                    InterceptlyTheme.radius.sm + 2,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  method.toUpperCase(),
                  style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
                    color: mStyle.text,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      _buildHighlightedSpan(
                        text: path,
                        query: highlightQuery,
                        normalStyle: InterceptlyTheme
                            .typography.bodyMediumMedium
                            .copyWith(
                          fontSize: 14,
                          height: 1.25,
                          color: colors.textPrimary,
                        ),
                        highlightStyle: InterceptlyTheme
                            .typography.bodyMediumMedium
                            .copyWith(
                          fontSize: 14,
                          height: 1.25,
                          backgroundColor: InterceptlyTheme.yellow500
                              .withValues(alpha: 0.28),
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (host.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text.rich(
                        _buildHighlightedSpan(
                          text: host,
                          query: highlightQuery,
                          normalStyle: InterceptlyTheme
                              .typography.bodySmallRegular
                              .copyWith(
                            fontSize: 12,
                            height: 1.2,
                            color: colors.textTertiary,
                            fontWeight: FontWeight.w500,
                          ),
                          highlightStyle: InterceptlyTheme
                              .typography.bodySmallRegular
                              .copyWith(
                            fontSize: 12,
                            height: 1.2,
                            backgroundColor: InterceptlyTheme.yellow500
                                .withValues(alpha: 0.28),
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (searchScopes != null && searchScopes!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final scope in SearchMatchScope.values)
                            if (searchScopes!.contains(scope))
                              _ScopeBadge(scope: scope),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 14,
                          color: metaColor,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _buildMetaLine(),
                            style: InterceptlyTheme.typography.labelMediumMedium
                                .copyWith(
                              fontSize: 12,
                              height: 1.2,
                              color: metaColor,
                              letterSpacing: 0.15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: statusLook.background,
                    borderRadius: BorderRadius.circular(10),
                    border: statusLook.border != null
                        ? Border.all(color: statusLook.border!)
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    child: isPending
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                statusLook.foreground,
                              ),
                            ),
                          )
                        : Text(
                            isErrorWithoutStatus ? 'ERR' : '$status',
                            style: InterceptlyTheme.typography.labelMediumBold
                                .copyWith(
                              fontSize: 12,
                              height: 1,
                              color: statusLook.foreground,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionCheckbox extends StatelessWidget {
  const _SelectionCheckbox({
    required this.isSelected,
    required this.actionColor,
    required this.onTap,
  });

  final bool isSelected;
  final Color actionColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: isSelected ? actionColor : InterceptlyGlobalColor.transparent,
          borderRadius: BorderRadius.circular(InterceptlyTheme.radius.sm),
          border: Border.all(
            color: isSelected ? actionColor : InterceptlyTheme.controlMuted,
            width: 1.5,
          ),
        ),
        child: isSelected
            ? Icon(Icons.check, size: 14, color: InterceptlyGlobalColor.white)
            : null,
      ),
    );
  }
}

class _ScopeBadge extends StatelessWidget {
  const _ScopeBadge({required this.scope});

  final SearchMatchScope scope;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (scope) {
      SearchMatchScope.url => (
          InterceptlyTheme.blue400,
          Icons.link_rounded,
        ),
      SearchMatchScope.headers => (
          InterceptlyTheme.yellow500,
          Icons.tag_rounded,
        ),
      SearchMatchScope.body => (
          InterceptlyTheme.green400,
          Icons.data_object_rounded,
        ),
      SearchMatchScope.error => (
          InterceptlyTheme.red400,
          Icons.error_outline_rounded,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(InterceptlyTheme.radius.sm),
        border: Border.all(
          color: color.withValues(alpha: 0.38),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10.5, color: color),
          const SizedBox(width: 3.5),
          Text(
            scope.label,
            style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1.1,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
