import 'package:flutter/material.dart';
import 'package:interceptly/src/model/realtime_frame.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

/// Header widget providing search input and direction/type filter chips for realtime frames.
class RealtimeFilterHeader extends StatelessWidget {
  final TextEditingController searchController;
  final String searchQuery;
  final FrameDirection? directionFilter;
  final FrameType? typeFilter;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final ValueChanged<FrameDirection?> onDirectionFilterChanged;
  final ValueChanged<FrameType?> onTypeFilterChanged;

  const RealtimeFilterHeader({
    super.key,
    required this.searchController,
    required this.searchQuery,
    required this.directionFilter,
    required this.typeFilter,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.onDirectionFilterChanged,
    required this.onTypeFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isAllSelected = directionFilter == null && typeFilter == null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16.0, 10.0, 16.0, 10.0),
      decoration: BoxDecoration(
        color: InterceptlyTheme.surface,
        border: Border(
          bottom: BorderSide(color: InterceptlyTheme.dividerSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: searchController,
            style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
              color: InterceptlyTheme.textPrimary,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'Search messages...',
              hintStyle: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                color: InterceptlyTheme.textMuted,
                fontSize: 13,
              ),
              prefixIcon: const Icon(
                Icons.search,
                size: 16,
                color: InterceptlyTheme.textMuted,
              ),
              suffixIcon: searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.clear,
                        size: 16,
                        color: InterceptlyTheme.textMuted,
                      ),
                      onPressed: onSearchCleared,
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 8.0,
              ),
              filled: true,
              fillColor: InterceptlyTheme.surfaceContainer,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(InterceptlyTheme.radius.md),
                borderSide: BorderSide(color: InterceptlyTheme.dividerSubtle),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(InterceptlyTheme.radius.md),
                borderSide: BorderSide(color: InterceptlyTheme.dividerSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(InterceptlyTheme.radius.md),
                borderSide: const BorderSide(color: InterceptlyTheme.indigo500),
              ),
            ),
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  key: const ValueKey('chip_all'),
                  label: 'All',
                  isSelected: isAllSelected,
                  onTap: () {
                    onDirectionFilterChanged(null);
                    onTypeFilterChanged(null);
                  },
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  key: const ValueKey('chip_incoming'),
                  label: '↓ IN',
                  isSelected: directionFilter == FrameDirection.incoming,
                  activeColor: InterceptlyTheme.green400,
                  activeBgColor:
                      InterceptlyTheme.green500.withValues(alpha: 0.15),
                  onTap: () {
                    onDirectionFilterChanged(
                      directionFilter == FrameDirection.incoming
                          ? null
                          : FrameDirection.incoming,
                    );
                  },
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  key: const ValueKey('chip_outgoing'),
                  label: '↑ OUT',
                  isSelected: directionFilter == FrameDirection.outgoing,
                  activeColor: InterceptlyTheme.blue400,
                  activeBgColor:
                      InterceptlyTheme.blue500.withValues(alpha: 0.15),
                  onTap: () {
                    onDirectionFilterChanged(
                      directionFilter == FrameDirection.outgoing
                          ? null
                          : FrameDirection.outgoing,
                    );
                  },
                ),
                const SizedBox(width: 8),
                Container(
                  height: 16,
                  width: 1,
                  color: InterceptlyTheme.dividerSubtle,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  key: const ValueKey('chip_text'),
                  label: 'Text',
                  isSelected: typeFilter == FrameType.text,
                  activeColor: InterceptlyTheme.indigo400,
                  activeBgColor:
                      InterceptlyTheme.indigo500.withValues(alpha: 0.15),
                  onTap: () {
                    onTypeFilterChanged(
                      typeFilter == FrameType.text ? null : FrameType.text,
                    );
                  },
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  key: const ValueKey('chip_binary'),
                  label: 'Binary',
                  isSelected: typeFilter == FrameType.binary,
                  activeColor: InterceptlyTheme.yellow400,
                  activeBgColor:
                      InterceptlyTheme.yellow500.withValues(alpha: 0.15),
                  onTap: () {
                    onTypeFilterChanged(
                      typeFilter == FrameType.binary ? null : FrameType.binary,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required Key key,
    required String label,
    required bool isSelected,
    Color? activeColor,
    Color? activeBgColor,
    required VoidCallback onTap,
  }) {
    final colors = InterceptlyTheme.colors;
    final fg = isSelected
        ? (activeColor ?? colors.actionPrimary)
        : colors.textSecondary;
    final bg = isSelected
        ? (activeBgColor ?? colors.actionPrimary.withValues(alpha: 0.12))
        : InterceptlyTheme.controlMuted;
    final border = isSelected
        ? (activeColor ?? colors.actionPrimary).withValues(alpha: 0.4)
        : InterceptlyTheme.dividerSubtle;

    return GestureDetector(
      key: key,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(InterceptlyTheme.radius.md),
          border: Border.all(color: border, width: 1.0),
        ),
        child: Text(
          label,
          style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
            color: fg,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
