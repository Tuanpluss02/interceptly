import 'package:flutter/material.dart';

import '../interceptly_theme.dart';

class FilterBadge extends StatelessWidget {
  final int activeFiltersCount;
  final VoidCallback onTap;

  const FilterBadge({
    super.key,
    required this.activeFiltersCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Badge.count(
      count: activeFiltersCount,
      backgroundColor: InterceptlyTheme.indigo500,
      child: IconButton(
        icon: const Icon(Icons.filter_list),
        onPressed: onTap,
        tooltip: 'Filters',
      ),
    );
  }
}
