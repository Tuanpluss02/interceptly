import 'package:flutter/material.dart';

import '../../model/domain_group.dart';
import '../interceptly_theme.dart';

class DomainGroupHeader extends StatelessWidget {
  final DomainGroup group;
  final VoidCallback onToggleExpand;

  const DomainGroupHeader({
    super.key,
    required this.group,
    required this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    final healthColor = group.hasErrors
        ? Color(0xFFEF4444) // Red for errors
        : group.hasWarnings
            ? Color(0xFFFCD34D) // Yellow for warnings
            : Color(0xFF2DD4BF); // Teal for success

    return Container(
      color: InterceptlyTheme.controlMuted,
      child: ListTile(
        leading: GestureDetector(
          onTap: onToggleExpand,
          child: Icon(
            group.isExpanded ? Icons.expand_less : Icons.expand_more,
            color: InterceptlyTheme.textSecondary,
          ),
        ),
        title: Text(
          group.domain,
          style: InterceptlyTheme.typography.bodyMediumMedium.copyWith(
            color: InterceptlyTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '${group.requestCount} request${group.requestCount > 1 ? 's' : ''} '
          '(${group.successCount} ok, ${group.errorCount} error${group.errorCount != 1 ? 's' : ''})',
          style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
            color: InterceptlyTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: healthColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: healthColor.withValues(alpha: 0.3)),
          ),
          child: Text(
            '${group.successCount}/${group.requestCount}',
            style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
              color: healthColor,
            ),
          ),
        ),
        onTap: onToggleExpand,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
    );
  }
}
