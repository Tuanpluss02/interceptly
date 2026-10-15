import 'package:flutter/material.dart';

import '../interceptly_theme.dart';

class FilterBadge extends StatelessWidget {
  final int activeFiltersCount;
  final VoidCallback? onTap;

  const FilterBadge({
    super.key,
    required this.activeFiltersCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = InterceptlyTheme.colors;
    final isActive = activeFiltersCount > 0;

    return Semantics(
      button: true,
      label:
          isActive ? 'Filters ($activeFiltersCount active)' : 'Filter requests',
      child: Badge.count(
        count: activeFiltersCount,
        isLabelVisible: isActive,
        backgroundColor: colors.actionPrimary,
        textColor: colors.textOnAction,
        textStyle: InterceptlyTheme.typography.labelSmallMedium.copyWith(
          fontSize: 10,
          color: colors.textOnAction,
        ),
        child: IconButton(
          icon: Icon(
            isActive ? Icons.filter_list_rounded : Icons.filter_list,
            size: 22,
            color: isActive ? colors.actionPrimary : colors.textSecondary,
          ),
          onPressed: onTap,
          tooltip: isActive
              ? 'Filter ($activeFiltersCount active)'
              : 'Filter requests',
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(),
        ),
      ),
    );
  }
}
