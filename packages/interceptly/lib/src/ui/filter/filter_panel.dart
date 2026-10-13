import 'package:flutter/material.dart';
import 'package:interceptly/src/model/request_filter.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

/// Filter bottom sheet for network request filtering.
///
/// Call [show] to present it as a modal bottom sheet.
class FilterPanel extends StatefulWidget {
  final RequestFilter currentFilter;
  final Set<String> availableDomains;
  final Function(RequestFilter) onFilterChanged;

  const FilterPanel({
    super.key,
    required this.currentFilter,
    required this.availableDomains,
    required this.onFilterChanged,
  });

  /// Shows the filter panel as a modal bottom sheet.
  static Future<void> show({
    required BuildContext context,
    required RequestFilter currentFilter,
    required Set<String> availableDomains,
    required Function(RequestFilter) onFilterChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FilterPanel(
        currentFilter: currentFilter,
        availableDomains: availableDomains,
        onFilterChanged: onFilterChanged,
      ),
    );
  }

  @override
  State<FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<FilterPanel> {
  late Set<String> selectedMethods;
  late bool include2xx;
  late bool include3xx;
  late bool include4xx;
  late bool include5xx;
  late Set<String> selectedDomains;

  static const _allMethods = {'GET', 'POST', 'PUT', 'DELETE', 'PATCH'};

  @override
  void initState() {
    selectedMethods = widget.currentFilter.methods.isEmpty
        ? Set.from(_allMethods)
        : Set.from(widget.currentFilter.methods);
    include2xx = widget.currentFilter.include2xx;
    include3xx = widget.currentFilter.include3xx;
    include4xx = widget.currentFilter.include4xx;
    include5xx = widget.currentFilter.include5xx;

    if (widget.currentFilter.domains.isEmpty) {
      selectedDomains = Set.from(widget.availableDomains);
    } else {
      selectedDomains = Set.from(widget.currentFilter.domains);
    }
    super.initState();
  }

  bool get _hasChanges {
    final allMethodsSelected = selectedMethods.containsAll(_allMethods) &&
        selectedMethods.length == _allMethods.length;
    final allDomainsSelected =
        selectedDomains.length == widget.availableDomains.length;
    return !allMethodsSelected ||
        !allDomainsSelected ||
        !include2xx ||
        !include3xx ||
        !include4xx ||
        !include5xx;
  }

  int get _activeFilterCount {
    int count = 0;
    if (!selectedMethods.containsAll(_allMethods) ||
        selectedMethods.length < _allMethods.length) {
      count += 1;
    }
    if (!include2xx || !include3xx || !include4xx || !include5xx) {
      count += 1;
    }
    if (!selectedDomains.containsAll(widget.availableDomains) ||
        selectedDomains.length < widget.availableDomains.length) {
      count += 1;
    }
    return count;
  }

  void _resetFilters() {
    setState(() {
      selectedMethods = Set.from(_allMethods);
      include2xx = true;
      include3xx = true;
      include4xx = true;
      include5xx = true;
      selectedDomains = Set.from(widget.availableDomains);
    });
  }

  void _applyFilters() {
    final allMethodsSelected = selectedMethods.containsAll(_allMethods) &&
        selectedMethods.length == _allMethods.length;
    final allDomainsSelected =
        selectedDomains.length == widget.availableDomains.length;

    widget.onFilterChanged(RequestFilter(
      methods: allMethodsSelected ? <String>{} : selectedMethods,
      include2xx: include2xx,
      include3xx: include3xx,
      include4xx: include4xx,
      include5xx: include5xx,
      domains: allDomainsSelected ? <String>{} : selectedDomains,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = InterceptlyTheme.themeData(context: context);
    final radius = InterceptlyTheme.radius;
    final spacing = InterceptlyTheme.spacing;
    final colors = InterceptlyTheme.colors;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Theme(
      data: theme,
      child: Container(
        margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 40),
        decoration: BoxDecoration(
          color: InterceptlyTheme.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(radius.lg * 2),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),

            Padding(
              padding:
                  EdgeInsets.fromLTRB(spacing.lg, spacing.sm, spacing.lg, 0),
              child: Row(
                children: [
                  Text(
                    'Filter',
                    style: InterceptlyTheme.typography.titleSmallBold.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  if (_activeFilterCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.actionPrimary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_activeFilterCount',
                        style: InterceptlyTheme.typography.labelSmallMedium
                            .copyWith(
                          color: colors.textOnAction,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (_hasChanges)
                    GestureDetector(
                      onTap: _resetFilters,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Text(
                          'Reset',
                          style: InterceptlyTheme.typography.bodySmallMedium
                              .copyWith(
                            color: colors.actionPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  spacing.lg,
                  spacing.lg,
                  spacing.lg,
                  bottomPadding + spacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(label: 'HTTP Methods'),
                    SizedBox(height: spacing.sm),
                    _MethodChips(
                      selected: selectedMethods,
                      onToggle: (m) => setState(() {
                        if (selectedMethods.contains(m)) {
                          selectedMethods.remove(m);
                        } else {
                          selectedMethods.add(m);
                        }
                      }),
                    ),
                    SizedBox(height: spacing.xl),

                    _SectionHeader(label: 'Status Codes'),
                    SizedBox(height: spacing.sm),
                    _StatusRow(
                      include2xx: include2xx,
                      include3xx: include3xx,
                      include4xx: include4xx,
                      include5xx: include5xx,
                      onToggle: (key) => setState(() {
                        switch (key) {
                          case '2xx':
                            include2xx = !include2xx;
                            break;
                          case '3xx':
                            include3xx = !include3xx;
                            break;
                          case '4xx':
                            include4xx = !include4xx;
                            break;
                          case '5xx':
                            include5xx = !include5xx;
                            break;
                        }
                      }),
                    ),
                    SizedBox(height: spacing.xl),

                    if (widget.availableDomains.isNotEmpty) ...[
                      _SectionHeader(
                        label: 'Domains',
                        subtitle:
                            '${selectedDomains.length} of ${widget.availableDomains.length} selected',
                      ),
                      SizedBox(height: spacing.sm),
                      _DomainList(
                        domains: widget.availableDomains,
                        selected: selectedDomains,
                        onToggle: (d) => setState(() {
                          if (selectedDomains.contains(d)) {
                            selectedDomains.remove(d);
                          } else {
                            selectedDomains.add(d);
                          }
                        }),
                        onSelectAll: () => setState(() {
                          selectedDomains = Set.from(widget.availableDomains);
                        }),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            Container(
              padding: EdgeInsets.fromLTRB(
                spacing.lg,
                spacing.md,
                spacing.lg,
                bottomPadding + spacing.md,
              ),
              decoration: BoxDecoration(
                color: InterceptlyTheme.surface,
                border: Border(
                  top: BorderSide(color: InterceptlyTheme.dividerSubtle),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _applyFilters,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.actionPrimary,
                    foregroundColor: colors.textOnAction,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(radius.md),
                    ),
                  ),
                  child: Text(
                    'Apply Filter${_activeFilterCount > 0 ? ' ($_activeFilterCount)' : ''}',
                    style: InterceptlyTheme.typography.labelMediumMedium,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.subtitle});

  final String label;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = InterceptlyTheme.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
            color: colors.textTertiary,
            letterSpacing: 0.8,
            fontSize: 11,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: InterceptlyTheme.typography.bodySmallRegular.copyWith(
              color: colors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

class _MethodChips extends StatelessWidget {
  const _MethodChips({required this.selected, required this.onToggle});

  final Set<String> selected;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: {'GET', 'POST', 'PUT', 'DELETE', 'PATCH'}.map((method) {
        final style = InterceptlyTheme.getMethodStyle(method);
        final isSelected = selected.contains(method);

        return _Chip(
          label: method,
          isSelected: isSelected,
          activeColor: style.text,
          activeBgColor: style.bg,
          activeBorderColor: style.border,
          onTap: () => onToggle(method),
        );
      }).toList(),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.include2xx,
    required this.include3xx,
    required this.include4xx,
    required this.include5xx,
    required this.onToggle,
  });

  final bool include2xx;
  final bool include3xx;
  final bool include4xx;
  final bool include5xx;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatusToggle(
          label: '2xx',
          isIncluded: include2xx,
          color: InterceptlyTheme.getStatusStyle(200).bg,
          onTap: () => onToggle('2xx'),
        ),
        const SizedBox(width: 8),
        _StatusToggle(
          label: '3xx',
          isIncluded: include3xx,
          color: InterceptlyTheme.getStatusStyle(301).bg,
          onTap: () => onToggle('3xx'),
        ),
        const SizedBox(width: 8),
        _StatusToggle(
          label: '4xx',
          isIncluded: include4xx,
          color: InterceptlyTheme.getStatusStyle(400).bg,
          onTap: () => onToggle('4xx'),
        ),
        const SizedBox(width: 8),
        _StatusToggle(
          label: '5xx',
          isIncluded: include5xx,
          color: InterceptlyTheme.getStatusStyle(500).bg,
          onTap: () => onToggle('5xx'),
        ),
      ],
    );
  }
}

class _StatusToggle extends StatelessWidget {
  const _StatusToggle({
    required this.label,
    required this.isIncluded,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool isIncluded;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = InterceptlyTheme.colors;
    final radius = InterceptlyTheme.radius;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isIncluded
                ? color.withValues(alpha: 0.12)
                : InterceptlyTheme.controlMuted,
            borderRadius: BorderRadius.circular(radius.md),
            border: Border.all(
              color: isIncluded
                  ? color.withValues(alpha: 0.35)
                  : InterceptlyTheme.dividerSubtle,
              width: 1.2,
            ),
          ),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isIncluded ? color : colors.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
                  color: isIncluded ? color : colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DomainList extends StatelessWidget {
  const _DomainList({
    required this.domains,
    required this.selected,
    required this.onToggle,
    required this.onSelectAll,
  });

  final Set<String> domains;
  final Set<String> selected;
  final void Function(String) onToggle;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    final colors = InterceptlyTheme.colors;
    final radius = InterceptlyTheme.radius;
    final allSelected =
        selected.containsAll(domains) && selected.length == domains.length;
    final sorted = domains.toList()..sort();

    return Column(
      children: [
        GestureDetector(
          onTap: onSelectAll,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: allSelected
                  ? colors.actionPrimary.withValues(alpha: 0.1)
                  : InterceptlyTheme.controlMuted,
              borderRadius: BorderRadius.circular(radius.md),
              border: Border.all(
                color: allSelected
                    ? colors.actionPrimary.withValues(alpha: 0.3)
                    : InterceptlyTheme.dividerSubtle,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color:
                        allSelected ? colors.actionPrimary : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: allSelected
                          ? colors.actionPrimary
                          : colors.textTertiary,
                      width: 1.5,
                    ),
                  ),
                  child: allSelected
                      ? Icon(Icons.check, size: 12, color: colors.textOnAction)
                      : null,
                ),
                const SizedBox(width: 10),
                Text(
                  'All domains',
                  style: InterceptlyTheme.typography.bodySmallMedium.copyWith(
                    color: allSelected
                        ? colors.actionPrimary
                        : colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  '${sorted.length}',
                  style: InterceptlyTheme.typography.bodySmallRegular.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),

        if (!allSelected && sorted.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: InterceptlyTheme.surface,
              borderRadius: BorderRadius.circular(radius.md),
              border: Border.all(color: InterceptlyTheme.dividerSubtle),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: sorted.asMap().entries.map((entry) {
                final idx = entry.key;
                final domain = entry.value;
                final isSelected = selected.contains(domain);

                return Column(
                  children: [
                    GestureDetector(
                      onTap: () => onToggle(domain),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? colors.actionPrimary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isSelected
                                      ? colors.actionPrimary
                                      : colors.textTertiary,
                                  width: 1.5,
                                ),
                              ),
                              child: isSelected
                                  ? Icon(
                                      Icons.check,
                                      size: 12,
                                      color: colors.textOnAction,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                domain,
                                style: InterceptlyTheme
                                    .typography.bodySmallMedium
                                    .copyWith(
                                  color: isSelected
                                      ? colors.actionPrimary
                                      : colors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (idx < sorted.length - 1)
                      Divider(
                        height: 1,
                        color: InterceptlyTheme.dividerSubtle,
                        indent: 42,
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.isSelected,
    required this.activeColor,
    required this.activeBgColor,
    required this.activeBorderColor,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final Color activeColor;
  final Color activeBgColor;
  final Color activeBorderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = InterceptlyTheme.colors;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeBgColor : InterceptlyTheme.controlMuted,
          borderRadius: BorderRadius.circular(InterceptlyTheme.radius.md),
          border: Border.all(
            color:
                isSelected ? activeBorderColor : InterceptlyTheme.dividerSubtle,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: InterceptlyTheme.typography.labelMediumMedium.copyWith(
            color: isSelected ? activeColor : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
