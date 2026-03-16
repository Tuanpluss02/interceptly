import 'package:flutter/material.dart';

import '../../model/request_filter.dart';
import '../interceptly_theme.dart';

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

  @override
  void initState() {
    selectedMethods = Set.from(widget.currentFilter.methods);
    include2xx = widget.currentFilter.include2xx;
    include3xx = widget.currentFilter.include3xx;
    include4xx = widget.currentFilter.include4xx;
    include5xx = widget.currentFilter.include5xx;

    // If empty domain filter, it means all are allowed
    if (widget.currentFilter.domains.isEmpty) {
      selectedDomains = Set.from(widget.availableDomains);
    } else {
      selectedDomains = Set.from(widget.currentFilter.domains);
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: InterceptlyTheme.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Handle & Header
          Container(
            padding: const EdgeInsets.only(top: 12.0, bottom: 12.0),
            decoration: BoxDecoration(
              color: InterceptlyTheme.surface,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border(
                bottom: BorderSide(color: InterceptlyTheme.dividerSubtle),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 6,
                  decoration: BoxDecoration(
                    color: InterceptlyTheme.controlMuted,
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filter Requests',
                        style:
                            InterceptlyTheme.typography.titleSmallBold.copyWith(
                          color: InterceptlyTheme.textPrimary,
                        ),
                      ),
                      TextButton(
                        onPressed: _resetFilters,
                        child: Text(
                          'Reset',
                          style: InterceptlyTheme.typography.titleMediumRegular
                              .copyWith(
                            color: InterceptlyTheme.indigo500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // Methods Filter
                _buildSectionTitle('HTTP Methods'),
                _buildSectionCard([_buildMethodsSection()]),
                SizedBox(height: 16),

                // Status Codes Filter
                _buildSectionTitle('Status Codes'),
                _buildSectionCard([_buildStatusCodesSection()]),
                SizedBox(height: 16),

                // Domains Filter
                if (widget.availableDomains.isNotEmpty) ...[
                  _buildSectionTitle('Domains'),
                  _buildSectionCard([_buildDomainsSection()]),
                ],
              ],
            ),
          ),

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
                  style: InterceptlyTheme.typography.labelMediumMedium.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title.toUpperCase(),
        style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
          color: InterceptlyTheme.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSectionCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: InterceptlyTheme.controlMuted,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildMethodsSection() {
    const methods = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'];

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Wrap(
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
            showCheckmark: false,
            selectedColor: InterceptlyTheme.indigo500.withValues(alpha: 0.15),
            labelStyle: TextStyle(
              color: isSelected
                  ? InterceptlyTheme.indigo500
                  : InterceptlyTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            side: BorderSide(
              color:
                  isSelected ? InterceptlyTheme.indigo500 : Colors.transparent,
            ),
            backgroundColor: InterceptlyTheme.surface,
          );
        }).toList(),
      ),
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

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Wrap(
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
                const SizedBox(width: 8),
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
            showCheckmark: false,
            selectedColor: statusColors[label]!.withValues(alpha: 0.15),
            labelStyle: TextStyle(
              color: isSelected
                  ? statusColors[label]
                  : InterceptlyTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            side: BorderSide(
              color: isSelected ? statusColors[label]! : Colors.transparent,
            ),
            backgroundColor: InterceptlyTheme.surface,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDomainsSection() {
    final sortedDomains = widget.availableDomains.toList()..sort();

    return Column(
      children: sortedDomains.asMap().entries.map((entry) {
        final index = entry.key;
        final domain = entry.value;
        final isSelected = selectedDomains.contains(domain);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: CheckboxListTile(
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
              ),
            ),
            if (index < sortedDomains.length - 1)
              Divider(
                height: 1,
                color: InterceptlyTheme.dividerSubtle,
                indent: 16,
              ),
          ],
        );
      }).toList(),
    );
  }

  void _resetFilters() {
    setState(() {
      selectedMethods = {'GET', 'POST', 'PUT', 'DELETE', 'PATCH'};
      include2xx = true;
      include3xx = true;
      include4xx = true;
      include5xx = true;
      selectedDomains = Set.from(widget.availableDomains);
    });
  }

  void _applyFilters() {
    // If all domains are selected, represent it as an empty set so future domains match too
    final appliedDomains =
        selectedDomains.length == widget.availableDomains.length
            ? <String>{}
            : selectedDomains;

    final newFilter = RequestFilter(
      methods: selectedMethods,
      include2xx: include2xx,
      include3xx: include3xx,
      include4xx: include4xx,
      include5xx: include5xx,
      domains: appliedDomains,
    );
    widget.onFilterChanged(newFilter);
    Navigator.pop(context);
  }
}
