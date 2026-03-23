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

  static const _allMethods = {'GET', 'POST', 'PUT', 'DELETE', 'PATCH'};

  @override
  void initState() {
    // Empty methods set means "show all" — display all chips as selected.
    selectedMethods = widget.currentFilter.methods.isEmpty
        ? Set.from(_allMethods)
        : Set.from(widget.currentFilter.methods);
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
                _buildSectionTitle('Methods'),
                _buildMethodsSection(),
                SizedBox(height: 24),

                // Status Codes Filter
                _buildSectionTitle('Status Codes'),
                _buildStatusCodesSection(),
                SizedBox(height: 24),

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
        style: TextStyle(
          color: InterceptlyTheme.colors.textTertiary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
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

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: methods.map((method) {
        final isSelected = selectedMethods.contains(method);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                selectedMethods.remove(method);
              } else {
                selectedMethods.add(method);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? InterceptlyTheme.indigo500.withValues(alpha: 0.1)
                  : InterceptlyTheme.controlMuted,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? InterceptlyTheme.indigo500.withValues(alpha: 0.5)
                    : InterceptlyTheme.dividerSubtle,
              ),
            ),
            child: Text(
              method,
              style: TextStyle(
                color: isSelected
                    ? InterceptlyTheme.indigo500
                    : InterceptlyTheme.colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
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
      '2xx': InterceptlyTheme.green500, // green-500
      '3xx': InterceptlyTheme.yellow500, // yellow-500
      '4xx': const Color(0xFFF97316), // orange-500 (keep for specific warning)
      '5xx': InterceptlyTheme.red500, // red-500
    };

    return Wrap(
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
        final baseColor = statusColors[label]!;

        return GestureDetector(
          onTap: () {
            setState(() {
              switch (key) {
                case 'include2xx':
                  include2xx = !isSelected;
                  break;
                case 'include3xx':
                  include3xx = !isSelected;
                  break;
                case 'include4xx':
                  include4xx = !isSelected;
                  break;
                case 'include5xx':
                  include5xx = !isSelected;
                  break;
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? baseColor.withValues(alpha: 0.1)
                  : InterceptlyTheme.controlMuted,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? baseColor.withValues(alpha: 0.5)
                    : InterceptlyTheme.dividerSubtle,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: baseColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color:
                        isSelected ? baseColor : InterceptlyTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
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
      selectedMethods = Set.from(_allMethods);
      include2xx = true;
      include3xx = true;
      include4xx = true;
      include5xx = true;
      selectedDomains = Set.from(widget.availableDomains);
    });
  }

  void _applyFilters() {
    // All selected == no filter (empty set = show all).
    final appliedMethods =
        selectedMethods.containsAll(_allMethods) && selectedMethods.length == _allMethods.length
            ? <String>{}
            : selectedMethods;
    final appliedDomains =
        selectedDomains.length == widget.availableDomains.length
            ? <String>{}
            : selectedDomains;

    final newFilter = RequestFilter(
      methods: appliedMethods,
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
