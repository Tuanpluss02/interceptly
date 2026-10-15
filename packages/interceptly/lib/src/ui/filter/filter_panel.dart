import 'package:flutter/material.dart';
import 'package:interceptly/src/model/request_filter.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/widgets/interceptly_text_field.dart';

/// Filter bottom sheet for network request filtering.
///
/// Designed exclusively with [InterceptlyTheme] tokens to prevent theme
/// leakage from the host application.
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

  String _domainSearchQuery = '';
  final TextEditingController _domainSearchController = TextEditingController();

  static const _allMethods = {'GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD'};

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _domainSearchController.dispose();
    super.dispose();
  }

  int get _activeStatusCount =>
      (include2xx ? 1 : 0) +
      (include3xx ? 1 : 0) +
      (include4xx ? 1 : 0) +
      (include5xx ? 1 : 0);

  bool get _canApply {
    if (selectedMethods.isEmpty) return false;
    if (_activeStatusCount == 0) return false;
    if (widget.availableDomains.isNotEmpty && selectedDomains.isEmpty) {
      return false;
    }
    return true;
  }

  int get _activeFilterCount {
    int count = 0;
    if (!selectedMethods.containsAll(_allMethods) ||
        selectedMethods.length < _allMethods.length) {
      count++;
    }
    if (!include2xx || !include3xx || !include4xx || !include5xx) {
      count++;
    }
    if (selectedDomains.isNotEmpty &&
        (!selectedDomains.containsAll(widget.availableDomains) ||
            selectedDomains.length < widget.availableDomains.length)) {
      count++;
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
      _domainSearchQuery = '';
      _domainSearchController.clear();
    });
  }

  void _applyFilters() {
    final allMethodsSelected = selectedMethods.containsAll(_allMethods) &&
        selectedMethods.length == _allMethods.length;
    final allDomainsSelected =
        selectedDomains.length == widget.availableDomains.length;

    widget.onFilterChanged(widget.currentFilter.copyWith(
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
        margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 36),
        decoration: BoxDecoration(
          color: InterceptlyTheme.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(radius.lg * 1.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(spacing.lg, spacing.sm, spacing.lg, spacing.sm),
              child: Row(
                children: [
                  Text(
                    'Filter Requests',
                    style: InterceptlyTheme.typography.titleSmallBold.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  if (_activeFilterCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.actionPrimary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_activeFilterCount',
                        style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
                          color: colors.textOnAction,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  GestureDetector(
                    onTap: _resetFilters,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'Reset All',
                        style: InterceptlyTheme.typography.bodySmallMedium.copyWith(
                          color: colors.actionPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: InterceptlyTheme.dividerSubtle),

            // Filter content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  spacing.lg,
                  spacing.md,
                  spacing.lg,
                  bottomPadding + spacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: HTTP Methods
                    _SectionHeader(label: 'HTTP Methods'),
                    SizedBox(height: spacing.sm),
                    _buildMethodChips(),
                    SizedBox(height: spacing.lg),

                    // Section 2: Status Codes
                    _SectionHeader(label: 'Status Code Ranges'),
                    SizedBox(height: spacing.sm),
                    _buildStatusGrid(radius),
                    SizedBox(height: spacing.lg),

                    // Section 3: Domains
                    if (widget.availableDomains.isNotEmpty) ...[
                      _SectionHeader(
                        label: 'Domains',
                        subtitle:
                            '${selectedDomains.length} of ${widget.availableDomains.length} selected',
                      ),
                      SizedBox(height: spacing.sm),
                      _buildDomainSection(radius, colors, spacing),
                    ],
                  ],
                ),
              ),
            ),

            // Footer Apply Button
            Container(
              padding: EdgeInsets.fromLTRB(
                spacing.lg,
                spacing.md,
                spacing.lg,
                bottomPadding + spacing.md,
              ),
              decoration: BoxDecoration(
                color: InterceptlyTheme.surface,
                border: Border(top: BorderSide(color: InterceptlyTheme.dividerSubtle)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _canApply ? _applyFilters : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.actionPrimary,
                    foregroundColor: colors.textOnAction,
                    disabledBackgroundColor: InterceptlyTheme.controlMuted,
                    disabledForegroundColor: colors.textTertiary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(radius.md),
                    ),
                  ),
                  child: Text(
                    _canApply
                        ? 'Apply Filter${_activeFilterCount > 0 ? ' ($_activeFilterCount)' : ''}'
                        : 'Select at least one domain',
                    style: InterceptlyTheme.typography.labelMediumMedium.copyWith(
                      color: _canApply ? colors.textOnAction : colors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _allMethods.map((method) {
        final style = InterceptlyTheme.getMethodStyle(method);
        final isSelected = selectedMethods.contains(method);

        return _MethodChip(
          label: method,
          isSelected: isSelected,
          style: style,
          onTap: () {
            setState(() {
              if (isSelected) {
                // Ensure at least 1 method remains selected
                if (selectedMethods.length > 1) {
                  selectedMethods.remove(method);
                }
              } else {
                selectedMethods.add(method);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildStatusGrid(InterceptlyRadius radius) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatusCard(
                label: '2xx Success',
                isIncluded: include2xx,
                color: InterceptlyTheme.getStatusStyle(200).bg,
                onTap: () {
                  if (include2xx && _activeStatusCount <= 1) return;
                  setState(() => include2xx = !include2xx);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatusCard(
                label: '3xx Redirect',
                isIncluded: include3xx,
                color: InterceptlyTheme.getStatusStyle(301).bg,
                onTap: () {
                  if (include3xx && _activeStatusCount <= 1) return;
                  setState(() => include3xx = !include3xx);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _StatusCard(
                label: '4xx Client Err',
                isIncluded: include4xx,
                color: InterceptlyTheme.getStatusStyle(400).bg,
                onTap: () {
                  if (include4xx && _activeStatusCount <= 1) return;
                  setState(() => include4xx = !include4xx);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatusCard(
                label: '5xx Server Err',
                isIncluded: include5xx,
                color: InterceptlyTheme.getStatusStyle(500).bg,
                onTap: () {
                  if (include5xx && _activeStatusCount <= 1) return;
                  setState(() => include5xx = !include5xx);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDomainSection(
    InterceptlyRadius radius,
    InterceptlyColors colors,
    InterceptlySpacing spacing,
  ) {
    final allSelected = selectedDomains.containsAll(widget.availableDomains) &&
        selectedDomains.length == widget.availableDomains.length;
    final sortedDomains = widget.availableDomains.toList()..sort();
    final filteredDomains = _domainSearchQuery.isEmpty
        ? sortedDomains
        : sortedDomains
            .where((d) => d.toLowerCase().contains(_domainSearchQuery))
            .toList();

    return Column(
      children: [
        if (widget.availableDomains.length > 4) ...[
          InterceptlySearchField(
            controller: _domainSearchController,
            hintText: 'Search domains...',
            onChanged: (q) => setState(() => _domainSearchQuery = q.trim().toLowerCase()),
          ),
          SizedBox(height: spacing.sm),
        ],

        // Select All row
        Row(
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  if (allSelected) {
                    selectedDomains.clear();
                  } else {
                    selectedDomains = Set.from(widget.availableDomains);
                  }
                });
              },
              child: Text(
                allSelected ? 'Deselect All' : 'Select All',
                style: InterceptlyTheme.typography.bodySmallMedium.copyWith(
                  color: colors.actionPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.sm),

        // Domain list card
        Container(
          decoration: BoxDecoration(
            color: InterceptlyTheme.surfaceContainer,
            borderRadius: BorderRadius.circular(radius.md),
            border: Border.all(color: InterceptlyTheme.dividerSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: filteredDomains.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: Text(
                      'No matching domains',
                      style: InterceptlyTheme.typography.bodySmallRegular.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredDomains.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: InterceptlyTheme.dividerSubtle,
                    indent: 40,
                  ),
                  itemBuilder: (context, index) {
                    final domain = filteredDomains[index];
                    final isChecked = selectedDomains.contains(domain);

                    return InkWell(
                      onTap: () {
                        setState(() {
                          if (isChecked) {
                            selectedDomains.remove(domain);
                          } else {
                            selectedDomains.add(domain);
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: isChecked ? colors.actionPrimary : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isChecked ? colors.actionPrimary : colors.textTertiary,
                                  width: 1.5,
                                ),
                              ),
                              child: isChecked
                                  ? Icon(Icons.check, size: 12, color: colors.textOnAction)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                domain,
                                style: InterceptlyTheme.typography.bodySmallMedium.copyWith(
                                  color: isChecked ? colors.textPrimary : colors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
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
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: InterceptlyTheme.typography.bodySmallRegular.copyWith(
              color: colors.textTertiary,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({
    required this.label,
    required this.isSelected,
    required this.style,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final MethodStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = InterceptlyTheme.colors;

    final bg = isSelected ? style.bg : InterceptlyTheme.surfaceContainer;
    final border = isSelected
        ? Border.all(color: style.border, width: 1.2)
        : Border.all(color: InterceptlyTheme.dividerSubtle, width: 1.0);
    final textColor = isSelected ? style.text : colors.textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(InterceptlyTheme.radius.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(InterceptlyTheme.radius.md),
            border: border,
          ),
          child: Text(
            label,
            style: InterceptlyTheme.typography.labelMediumMedium.copyWith(
              color: textColor,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
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

    final bg = isIncluded
        ? color.withValues(alpha: 0.14)
        : InterceptlyTheme.surfaceContainer;
    final border = isIncluded
        ? Border.all(color: color.withValues(alpha: 0.6), width: 1.2)
        : Border.all(color: InterceptlyTheme.dividerSubtle, width: 1.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius.md),
            border: border,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isIncluded ? color : colors.textTertiary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
                    color: isIncluded ? color : colors.textSecondary,
                    fontWeight: isIncluded ? FontWeight.w600 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
