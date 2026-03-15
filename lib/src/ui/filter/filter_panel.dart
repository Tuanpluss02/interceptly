import 'package:flutter/material.dart';

import '../../model/request_filter.dart';
import '../interceptly_theme.dart';

class FilterPanel extends StatefulWidget {
  final RequestFilter currentFilter;
  final Set<String> availableDomains;
  final bool groupingEnabled;
  final Function(RequestFilter) onFilterChanged;
  final Function(bool) onGroupingToggled;

  const FilterPanel({
    super.key,
    required this.currentFilter,
    required this.availableDomains,
    required this.groupingEnabled,
    required this.onFilterChanged,
    required this.onGroupingToggled,
  });

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
  late bool groupingEnabled;

  @override
  void initState() {
    selectedMethods = Set.from(widget.currentFilter.methods);
    include2xx = widget.currentFilter.include2xx;
    include3xx = widget.currentFilter.include3xx;
    include4xx = widget.currentFilter.include4xx;
    include5xx = widget.currentFilter.include5xx;
    selectedDomains = Set.from(widget.currentFilter.domains);
    groupingEnabled = widget.groupingEnabled;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        color: InterceptlyTheme.surface,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Filter Options',
                    style: InterceptlyTheme.typography.titleSmallBold.copyWith(
                      color: InterceptlyTheme.textPrimary,
                    ),
                  ),
                  TextButton(
                    onPressed: _resetFilters,
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),
            Divider(color: InterceptlyTheme.dividerSubtle, height: 0),
            // Content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // Group by Domain Toggle
                  _buildGroupByDomainSection(),
                  SizedBox(height: 24),
                  // Methods Filter
                  _buildMethodsSection(),
                  SizedBox(height: 24),
                  // Status Codes Filter
                  _buildStatusCodesSection(),
                  SizedBox(height: 24),
                  // Domains Filter
                  if (widget.availableDomains.isNotEmpty)
                    _buildDomainsSection(),
                ],
              ),
            ),
            Divider(color: InterceptlyTheme.dividerSubtle, height: 0),
            // Footer with Apply button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _applyFilters,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: InterceptlyTheme.indigo500,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Apply Filters',
                    style:
                        InterceptlyTheme.typography.labelSmallMedium.copyWith(
                      color: Colors.white,
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

  Widget _buildGroupByDomainSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: InterceptlyTheme.controlMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: InterceptlyTheme.dividerSubtle),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Group by Domain',
                  style: InterceptlyTheme.typography.bodyMediumMedium.copyWith(
                    color: InterceptlyTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Organize list by host URL',
                  style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                    color: InterceptlyTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: groupingEnabled,
              onChanged: (value) {
                setState(() => groupingEnabled = value);
              },
              activeThumbColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodsSection() {
    const methods = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'METHODS',
          style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
            color: InterceptlyTheme.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: methods.map((method) {
            final isSelected = selectedMethods.contains(method);
            return FilterChip(
              label: Text(method),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    selectedMethods.add(method);
                  } else {
                    selectedMethods.remove(method);
                  }
                });
              },
              selectedColor: InterceptlyTheme.indigo500.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                color: isSelected
                    ? InterceptlyTheme.indigo500
                    : InterceptlyTheme.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              side: BorderSide(
                color: isSelected
                    ? InterceptlyTheme.indigo500
                    : InterceptlyTheme.dividerSubtle,
              ),
              backgroundColor: InterceptlyTheme.surface,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildStatusCodesSection() {
    const statusGroups = [
      ('2xx', 'include2xx'),
      ('3xx', 'include3xx'),
      ('4xx', 'include4xx'),
      ('5xx', 'include5xx'),
    ];

    final statusColors = {
      '2xx': Color(0xFF2DD4BF),
      '3xx': Color(0xFFFCD34D),
      '4xx': Color(0xFFF97316),
      '5xx': Color(0xFFEF4444),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STATUS CODES',
          style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
            color: InterceptlyTheme.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: statusGroups.map((group) {
            final label = group.$1;
            final key = group.$2;
            final isSelected = key == 'include2xx'
                ? include2xx
                : key == 'include3xx'
                    ? include3xx
                    : key == 'include4xx'
                        ? include4xx
                        : include5xx;

            return FilterChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColors[label],
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(label),
                ],
              ),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  switch (key) {
                    case 'include2xx':
                      include2xx = selected;
                      break;
                    case 'include3xx':
                      include3xx = selected;
                      break;
                    case 'include4xx':
                      include4xx = selected;
                      break;
                    case 'include5xx':
                      include5xx = selected;
                      break;
                  }
                });
              },
              selectedColor: statusColors[label]!.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                color: isSelected
                    ? statusColors[label]
                    : InterceptlyTheme.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              side: BorderSide(
                color: isSelected
                    ? statusColors[label]!
                    : InterceptlyTheme.dividerSubtle,
              ),
              backgroundColor: InterceptlyTheme.surface,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDomainsSection() {
    final sortedDomains = widget.availableDomains.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DOMAINS',
          style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
            color: InterceptlyTheme.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: 12),
        ...sortedDomains.map((domain) {
          final isSelected = selectedDomains.contains(domain);
          return CheckboxListTile(
            value: isSelected,
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  selectedDomains.add(domain);
                } else {
                  selectedDomains.remove(domain);
                }
              });
            },
            title: Text(
              domain,
              style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                color: InterceptlyTheme.textPrimary,
              ),
            ),
            contentPadding: EdgeInsets.zero,
            checkColor: Colors.white,
            activeColor: InterceptlyTheme.indigo500,
          );
        }),
      ],
    );
  }

  void _resetFilters() {
    setState(() {
      selectedMethods.clear();
      include2xx = true;
      include3xx = true;
      include4xx = true;
      include5xx = true;
      selectedDomains.clear();
      groupingEnabled = false;
    });
  }

  void _applyFilters() {
    final newFilter = RequestFilter(
      methods: selectedMethods,
      include2xx: include2xx,
      include3xx: include3xx,
      include4xx: include4xx,
      include5xx: include5xx,
      domains: selectedDomains,
    );
    widget.onFilterChanged(newFilter);
    widget.onGroupingToggled(groupingEnabled);
    Navigator.pop(context);
  }
}
