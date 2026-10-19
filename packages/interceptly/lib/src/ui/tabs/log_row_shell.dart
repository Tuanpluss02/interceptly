import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

import '../../model/search_match_scope.dart';

/// Visual treatment for the status pill on list rows.
class LogStatusLook {
  const LogStatusLook({
    required this.background,
    required this.foreground,
    this.border,
  });

  /// Status pill colors for a REST row.
  factory LogStatusLook.rest({
    required int status,
    required bool isPending,
    required bool isErrorWithoutStatus,
    required InterceptlyColors palette,
  }) {
    if (isPending) {
      final s = InterceptlyTheme.getStatusStyle(status);
      return LogStatusLook(
        background: palette.surfaceTertiary,
        foreground: s.text,
      );
    }
    if (isErrorWithoutStatus) {
      return const LogStatusLook(
        background: InterceptlyTheme.red500,
        foreground: InterceptlyGlobalColor.white,
      );
    }
    if (status >= 200 && status < 300) {
      return LogStatusLook(
        background: InterceptlyTheme.green500.withValues(alpha: 0.14),
        foreground: InterceptlyTheme.green400,
        border: InterceptlyTheme.green500.withValues(alpha: 0.38),
      );
    }
    if (status >= 400 && status < 500) {
      return const LogStatusLook(
        background: InterceptlyTheme.yellow500,
        foreground: InterceptlyGlobalColor.black,
      );
    }
    if (status >= 500) {
      return const LogStatusLook(
        background: InterceptlyTheme.red500,
        foreground: InterceptlyGlobalColor.white,
      );
    }
    if (status == 101) {
      return const LogStatusLook(
        background: InterceptlyTheme.purple500,
        foreground: InterceptlyGlobalColor.white,
      );
    }
    final s = InterceptlyTheme.getStatusStyle(status);
    return LogStatusLook(background: s.bg, foreground: s.text);
  }

  /// Status pill colors for a realtime connection row.
  factory LogStatusLook.realtime({
    required int status,
    required bool isPending,
    required InterceptlyColors palette,
    bool hasError = false,
  }) {
    if (isPending) {
      return LogStatusLook(
        background: InterceptlyTheme.green500.withValues(alpha: 0.14),
        foreground: InterceptlyTheme.green400,
        border: InterceptlyTheme.green500.withValues(alpha: 0.38),
      );
    }
    if (hasError || (status > 1000 && status != 1005)) {
      return LogStatusLook(
        background: InterceptlyTheme.red500.withValues(alpha: 0.15),
        foreground: InterceptlyTheme.red400,
        border: InterceptlyTheme.red500.withValues(alpha: 0.38),
      );
    }
    return LogStatusLook(
      background: palette.surfaceTertiary,
      foreground: palette.textSecondary,
      border: InterceptlyTheme.dividerSubtle,
    );
  }

  final Color background;
  final Color foreground;
  final Color? border;
}

/// Splits a request URL into its path and host parts for two-line display.
({String path, String host}) splitLogUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri != null && uri.hasAuthority) {
    final pathWithQuery = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    final path = pathWithQuery.isEmpty ? '/' : pathWithQuery;
    return (path: path, host: uri.host);
  }
  return (path: url, host: '');
}

/// Builds a text span with every occurrence of [query] emphasized.
TextSpan buildLogHighlightedSpan({
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

/// HTTP method chip shown at the leading edge of a log row.
class LogMethodChip extends StatelessWidget {
  const LogMethodChip({super.key, required this.method});

  final String method;

  @override
  Widget build(BuildContext context) {
    final mStyle = InterceptlyTheme.getMethodStyle(method);
    return Container(
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
        style: InterceptlyTheme.typography.monospace(
          InterceptlyTheme.typography.labelSmallMedium.copyWith(
            color: mStyle.text,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

/// Status pill badge shown at the trailing edge of a log row title line.
class LogStatusBadge extends StatelessWidget {
  const LogStatusBadge._({
    required this.look,
    required this.content,
  });

  /// Plain numeric/text badge used by REST rows.
  factory LogStatusBadge.rest({
    required LogStatusLook look,
    required String label,
  }) {
    return LogStatusBadge._(
      look: look,
      content: Text(
        label,
        style: InterceptlyTheme.typography.monospace(
          InterceptlyTheme.typography.labelMediumBold.copyWith(
            fontSize: 12,
            height: 1,
            fontWeight: FontWeight.bold,
            color: look.foreground,
          ),
        ),
      ),
    );
  }

  /// Plain connection-state badge used by realtime rows.
  factory LogStatusBadge.realtime({
    required LogStatusLook look,
    required String label,
  }) {
    return LogStatusBadge._(
      look: look,
      content: Text(
        label,
        style: InterceptlyTheme.typography.monospace(
          InterceptlyTheme.typography.labelMediumBold.copyWith(
            fontSize: 10,
            height: 1,
            fontWeight: FontWeight.w700,
            color: look.foreground,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  /// Spinner badge used by pending REST rows.
  factory LogStatusBadge.spinner({required LogStatusLook look}) {
    return LogStatusBadge._(
      look: look,
      content: SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            look.foreground,
          ),
        ),
      ),
    );
  }

  /// Live-dot badge used by connected realtime rows.
  factory LogStatusBadge.liveDot({
    required LogStatusLook look,
    required String label,
  }) {
    return LogStatusBadge._(
      look: look,
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: look.foreground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: InterceptlyTheme.typography.monospace(
              InterceptlyTheme.typography.labelSmallBold.copyWith(
                fontSize: 10,
                height: 1,
                fontWeight: FontWeight.w700,
                color: look.foreground,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  final LogStatusLook look;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: look.background,
        borderRadius: BorderRadius.circular(10),
        border: look.border != null ? Border.all(color: look.border!) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 9,
          vertical: 5,
        ),
        child: content,
      ),
    );
  }
}

/// Checkbox shown at the leading edge of a row in selection mode.
class LogSelectionCheckbox extends StatelessWidget {
  const LogSelectionCheckbox({
    super.key,
    required this.isSelected,
    required this.actionColor,
    required this.onTap,
  });

  final bool isSelected;
  final Color actionColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: isSelected,
      label: 'Select request',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isSelected
                    ? actionColor
                    : InterceptlyGlobalColor.transparent,
                borderRadius: BorderRadius.circular(InterceptlyTheme.radius.sm),
                border: Border.all(
                  color:
                      isSelected ? actionColor : InterceptlyTheme.controlMuted,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? Icon(
                      Icons.check,
                      size: 14,
                      color: InterceptlyGlobalColor.white,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Search-match scope badge shown under the URL of a REST row.
class LogScopeBadge extends StatelessWidget {
  const LogScopeBadge({super.key, required this.scope});

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

/// Wrap of search-match scope badges under a REST row URL.
class LogScopeBadges extends StatelessWidget {
  const LogScopeBadges({super.key, required this.scopes});

  final Set<SearchMatchScope> scopes;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final scope in SearchMatchScope.values)
          if (scopes.contains(scope)) LogScopeBadge(scope: scope),
      ],
    );
  }
}

/// Single-line metadata text (time, duration, size or frame counts).
class LogMetaText extends StatelessWidget {
  const LogMetaText(this.data, {super.key});

  final String data;

  @override
  Widget build(BuildContext context) {
    final colors = InterceptlyTheme.colorsOf(context);
    return Text(
      data,
      style: InterceptlyTheme.typography.labelMediumMedium.copyWith(
        fontSize: 12,
        height: 1.2,
        color: colors.textTertiary,
        letterSpacing: 0.15,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Schedule-icon row wrapping the metadata line of a log row.
class LogMetaRow extends StatelessWidget {
  const LogMetaRow({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = InterceptlyTheme.colorsOf(context);
    return Row(
      children: [
        Icon(
          Icons.schedule_rounded,
          size: 14,
          color: colors.textTertiary,
        ),
        const SizedBox(width: 4),
        Expanded(child: child),
      ],
    );
  }
}

/// Shared card layout for log rows: method chip, two-line URL, status badge.
class LogRowShell extends StatelessWidget {
  const LogRowShell({
    super.key,
    required this.method,
    required this.url,
    required this.statusBadge,
    required this.meta,
    required this.onTap,
    this.onLongPress,
    this.highlightQuery,
    this.scopeBadges,
    this.isSelectionMode = false,
    this.isSelected = false,
    required this.semanticsLabel,
  });

  final String method;
  final String url;
  final Widget statusBadge;
  final Widget meta;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? highlightQuery;
  final Widget? scopeBadges;
  final bool isSelectionMode;
  final bool isSelected;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = InterceptlyTheme.colorsOf(context);
    final (:path, :host) = splitLogUrl(url);
    final borderRadius = BorderRadius.circular(InterceptlyTheme.radius.lg);

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
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
            padding:
                const EdgeInsets.symmetric(horizontal: 14.0, vertical: 14.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isSelectionMode) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: LogSelectionCheckbox(
                      isSelected: isSelected,
                      actionColor: colors.actionPrimary,
                      onTap: onTap,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                LogMethodChip(method: method),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text.rich(
                              buildLogHighlightedSpan(
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
                          ),
                          const SizedBox(width: 10),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: statusBadge,
                          ),
                        ],
                      ),
                      if (host.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text.rich(
                          buildLogHighlightedSpan(
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
                      if (scopeBadges != null) ...[
                        const SizedBox(height: 6),
                        scopeBadges!,
                      ],
                      const SizedBox(height: 6),
                      LogMetaRow(child: meta),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
