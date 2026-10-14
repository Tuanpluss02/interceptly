import 'package:flutter/material.dart';

import '../../model/request_filter.dart';
import '../../session/inspector_session_view.dart';
import '../interceptly_theme.dart';

/// A horizontal scrollable bar of preset filter chips.
///
/// Provides single-tap filtering for common criteria:
/// - "All": Resets filter to default
/// - "Errors": Toggles [RequestFilter.onlyErrors]
/// - "2xx", "3xx", "4xx", "5xx": Toggles specific status code ranges
/// - "GET", "POST": Toggles single HTTP methods
class QuickFilterBar extends StatelessWidget {
  const QuickFilterBar({
    super.key,
    required this.session,
  });

  final InspectorSessionView session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final filter = session.filter;
        final colors = InterceptlyTheme.colors;

        final isAllActive = filter.isEmpty;
        final isErrorsActive = filter.onlyErrors;
        final is2xxActive = filter.include2xx &&
            !filter.include3xx &&
            !filter.include4xx &&
            !filter.include5xx &&
            !filter.onlyErrors;
        final is3xxActive = filter.include3xx &&
            !filter.include2xx &&
            !filter.include4xx &&
            !filter.include5xx &&
            !filter.onlyErrors;
        final is4xxActive = filter.include4xx &&
            !filter.include2xx &&
            !filter.include3xx &&
            !filter.include5xx &&
            !filter.onlyErrors;
        final is5xxActive = filter.include5xx &&
            !filter.include2xx &&
            !filter.include3xx &&
            !filter.include4xx &&
            !filter.onlyErrors;
        final isGetActive =
            filter.methods.length == 1 && filter.methods.contains('GET');
        final isPostActive =
            filter.methods.length == 1 && filter.methods.contains('POST');

        return Container(
          height: 42,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _QuickChip(
                label: 'All',
                isSelected: isAllActive,
                activeColor: colors.actionPrimary,
                onTap: () => session.applyFilter(RequestFilter()),
              ),
              const SizedBox(width: 8),
              _QuickChip(
                label: 'Errors',
                icon: Icons.error_outline_rounded,
                isSelected: isErrorsActive,
                activeColor: colors.errorDefault,
                onTap: () {
                  if (isErrorsActive) {
                    session.applyFilter(filter.copyWith(onlyErrors: false));
                  } else {
                    session.applyFilter(filter.copyWith(onlyErrors: true));
                  }
                },
              ),
              const SizedBox(width: 8),
              _QuickChip(
                label: '2xx',
                isSelected: is2xxActive,
                activeColor: InterceptlyTheme.getStatusStyle(200).bg,
                onTap: () {
                  if (is2xxActive) {
                    session.applyFilter(filter.copyWith(
                      include2xx: true,
                      include3xx: true,
                      include4xx: true,
                      include5xx: true,
                    ));
                  } else {
                    session.applyFilter(filter.copyWith(
                      include2xx: true,
                      include3xx: false,
                      include4xx: false,
                      include5xx: false,
                      onlyErrors: false,
                    ));
                  }
                },
              ),
              const SizedBox(width: 8),
              _QuickChip(
                label: '3xx',
                isSelected: is3xxActive,
                activeColor: InterceptlyTheme.getStatusStyle(301).bg,
                onTap: () {
                  if (is3xxActive) {
                    session.applyFilter(filter.copyWith(
                      include2xx: true,
                      include3xx: true,
                      include4xx: true,
                      include5xx: true,
                    ));
                  } else {
                    session.applyFilter(filter.copyWith(
                      include2xx: false,
                      include3xx: true,
                      include4xx: false,
                      include5xx: false,
                      onlyErrors: false,
                    ));
                  }
                },
              ),
              const SizedBox(width: 8),
              _QuickChip(
                label: '4xx',
                isSelected: is4xxActive,
                activeColor: InterceptlyTheme.getStatusStyle(400).bg,
                onTap: () {
                  if (is4xxActive) {
                    session.applyFilter(filter.copyWith(
                      include2xx: true,
                      include3xx: true,
                      include4xx: true,
                      include5xx: true,
                    ));
                  } else {
                    session.applyFilter(filter.copyWith(
                      include2xx: false,
                      include3xx: false,
                      include4xx: true,
                      include5xx: false,
                      onlyErrors: false,
                    ));
                  }
                },
              ),
              const SizedBox(width: 8),
              _QuickChip(
                label: '5xx',
                isSelected: is5xxActive,
                activeColor: InterceptlyTheme.getStatusStyle(500).bg,
                onTap: () {
                  if (is5xxActive) {
                    session.applyFilter(filter.copyWith(
                      include2xx: true,
                      include3xx: true,
                      include4xx: true,
                      include5xx: true,
                    ));
                  } else {
                    session.applyFilter(filter.copyWith(
                      include2xx: false,
                      include3xx: false,
                      include4xx: false,
                      include5xx: true,
                      onlyErrors: false,
                    ));
                  }
                },
              ),
              const SizedBox(width: 8),
              _QuickChip(
                label: 'POST',
                isSelected: isPostActive,
                activeColor: InterceptlyTheme.getMethodStyle('POST').text,
                onTap: () {
                  if (isPostActive) {
                    session.applyFilter(filter.copyWith(methods: {}));
                  } else {
                    session.applyFilter(filter.copyWith(methods: {'POST'}));
                  }
                },
              ),
              const SizedBox(width: 8),
              _QuickChip(
                label: 'GET',
                isSelected: isGetActive,
                activeColor: InterceptlyTheme.getMethodStyle('GET').text,
                onTap: () {
                  if (isGetActive) {
                    session.applyFilter(filter.copyWith(methods: {}));
                  } else {
                    session.applyFilter(filter.copyWith(methods: {'GET'}));
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    this.icon,
    required this.isSelected,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = InterceptlyTheme.colors;

    final bg = isSelected
        ? activeColor.withValues(alpha: 0.16)
        : InterceptlyTheme.surfaceContainer;
    final border = isSelected
        ? Border.all(color: activeColor.withValues(alpha: 0.6), width: 1.2)
        : Border.all(color: InterceptlyTheme.dividerSubtle, width: 1.0);
    final textStyle = InterceptlyTheme.typography.labelSmallMedium.copyWith(
      color: isSelected ? activeColor : colors.textSecondary,
      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
      fontSize: 12,
    );

    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label quick filter',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(InterceptlyTheme.radius.full),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(InterceptlyTheme.radius.full),
              border: border,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 14,
                    color: isSelected ? activeColor : colors.textTertiary,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(label, style: textStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
