part of 'network_tab.dart';

// ── Top bar widgets ───────────────────────────────────────────────────────────

class _SelectionTopBar extends StatelessWidget {
  const _SelectionTopBar({
    required this.selectedCount,
    required this.colors,
    required this.onCancel,
  });

  final int selectedCount;
  final InterceptlyColors colors;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: InterceptlyTheme.controlMuted,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.close, size: 20, color: colors.textSecondary),
            onPressed: onCancel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Cancel selection',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$selectedCount selected',
              style: InterceptlyTheme.typography.bodyMediumMedium
                  .copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchFilterBar extends StatelessWidget {
  const _SearchFilterBar({
    required this.controller,
    required this.onChanged,
    required this.onShowFilter,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onShowFilter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: InterceptlySearchField(
              controller: controller,
              hintText: 'Search URL, headers, body…',
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.filter_list, size: 24),
            onPressed: onShowFilter,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            tooltip: 'Filter',
          ),
        ],
      ),
    );
  }
}

// ── Export bar ────────────────────────────────────────────────────────────────

class _ExportBar extends StatelessWidget {
  const _ExportBar({
    required this.selectedCount,
    required this.isExporting,
    required this.colors,
    required this.onExport,
  });

  final int selectedCount;
  final bool isExporting;
  final InterceptlyColors colors;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfacePrimary,
        border: Border(top: BorderSide(color: InterceptlyTheme.dividerSubtle)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: selectedCount == 0 || isExporting ? null : onExport,
            icon: isExporting
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.textOnAction,
                    ),
                  )
                : const Icon(Icons.upload_file, size: 18),
            label: Text(
              isExporting
                  ? 'Exporting…'
                  : 'Export $selectedCount to Postman',
              style: InterceptlyTheme.typography.bodyMediumMedium
                  .copyWith(color: colors.textOnAction),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.actionPrimary,
              foregroundColor: colors.textOnAction,
              disabledBackgroundColor: InterceptlyTheme.controlMuted,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(InterceptlyTheme.radius.md),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Selectable group header ───────────────────────────────────────────────────

class _SelectableGroupHeader extends StatelessWidget {
  const _SelectableGroupHeader({
    required this.group,
    required this.groupIds,
    required this.allSelected,
    required this.someSelected,
    required this.onToggleExpand,
    required this.onToggleGroupSelection,
  });

  final DomainGroup group;
  final List<String> groupIds;
  final bool allSelected;
  final bool someSelected;
  final VoidCallback onToggleExpand;
  final void Function(List<String>) onToggleGroupSelection;

  @override
  Widget build(BuildContext context) {
    final colors = InterceptlyTheme.colors;

    return Container(
      color: InterceptlyTheme.controlMuted,
      child: ListTile(
        leading: GestureDetector(
          onTap: onToggleExpand,
          child: Icon(
            group.isExpanded ? Icons.expand_less : Icons.expand_more,
            color: colors.textSecondary,
          ),
        ),
        title: Text(
          group.domain,
          style: InterceptlyTheme.typography.bodyMediumMedium.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '${group.requestCount} request${group.requestCount > 1 ? 's' : ''} '
          '(${group.successCount} ok, ${group.errorCount} error${group.errorCount != 1 ? 's' : ''})',
          style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
            color: colors.textSecondary,
            fontSize: 12,
          ),
        ),
        trailing: GestureDetector(
          onTap: () => onToggleGroupSelection(groupIds),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: allSelected
                  ? colors.actionPrimary
                  : someSelected
                      ? colors.actionPrimary.withValues(alpha: 0.3)
                      : InterceptlyGlobalColor.transparent,
              borderRadius: BorderRadius.circular(InterceptlyTheme.radius.sm),
              border: Border.all(
                color: allSelected || someSelected
                    ? colors.actionPrimary
                    : InterceptlyTheme.dividerSubtle.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            child: allSelected
                ? Icon(Icons.check, size: 14, color: colors.textOnAction)
                : someSelected
                    ? Icon(Icons.remove, size: 14, color: colors.textOnAction)
                    : null,
          ),
        ),
        onTap: onToggleExpand,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
    );
  }
}
