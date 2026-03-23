import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/detail/share_handler.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/widgets/error_summary.dart';
import 'package:interceptly/src/ui/widgets/domain_group_header.dart';
import 'package:interceptly/src/ui/widgets/interceptly_text_field.dart';
import 'package:interceptly/src/ui/widgets/toast_notification.dart';

import '../../model/domain_group.dart';
import '../../model/request_record.dart';
import '../../session/inspector_session.dart';

class NetworkTab extends StatefulWidget {
  const NetworkTab({
    super.key,
    required this.session,
    this.groupingEnabled = false,
    this.onShowFilterPanel,
  });

  final InspectorSession session;
  final bool groupingEnabled;
  final VoidCallback? onShowFilterPanel;

  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<NetworkTab> {
  late TextEditingController _searchController;

  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.session.masterQuery ?? '',
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleGroupSelection(List<String> groupIds) {
    setState(() {
      final allSelected = groupIds.every((id) => _selectedIds.contains(id));
      if (allSelected) {
        _selectedIds.removeAll(groupIds);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.addAll(groupIds);
      }
    });
  }

  Future<void> _exportSelectedAsPostman() async {
    if (_selectedIds.isEmpty || _isExporting) return;
    setState(() => _isExporting = true);

    try {
      // Always resolve through getFilteredRecords() → IndexEntry, which
      // carries bodyLocation / fileOffset so loadDetail works correctly.
      final allEntries = widget.session.getFilteredRecords();
      final selectedEntries =
          allEntries.where((e) => _selectedIds.contains(e.id)).toList();

      final records = <RequestRecord>[];
      for (final entry in selectedEntries) {
        records.add(await widget.session.loadDetail(entry));
      }

      if (!mounted) return;

      await ShareHandler(
        context: context,
        fabKey: GlobalKey(),
      ).exportPostmanRecords(records);

      if (mounted) _exitSelectionMode();
    } catch (e) {
      if (mounted) {
        ToastNotification.show('Export failed: $e', contextHint: context);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_searchController.text != (widget.session.masterQuery ?? '')) {
      _searchController.text = widget.session.masterQuery ?? '';
    }

    final colors = InterceptlyTheme.colors;

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isSelectionMode) _exitSelectionMode();
      },
      child: Scaffold(
        body: Column(
          children: [
            // ── Top bar: selection header OR search+filter ──────────────────
            if (_isSelectionMode)
              Container(
                color: InterceptlyTheme.controlMuted,
                padding: const EdgeInsets.symmetric(
                    horizontal: 8.0, vertical: 8.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 20,
                        color: colors.textSecondary,
                      ),
                      onPressed: _exitSelectionMode,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Cancel selection',
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${_selectedIds.length} selected',
                        style:
                            InterceptlyTheme.typography.bodyMediumMedium
                                .copyWith(color: colors.textPrimary),
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: InterceptlySearchField(
                        controller: _searchController,
                        hintText: 'Search URL, headers, body…',
                        onChanged: (value) {
                          final q = value.trim();
                          if (q.isEmpty) {
                            widget.session.cancelMasterSearch();
                          } else {
                            widget.session.startMasterSearch(q);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.filter_list, size: 24),
                      onPressed: widget.onShowFilterPanel,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                      tooltip: 'Filter',
                    ),
                  ],
                ),
              ),

            Divider(height: 1, color: InterceptlyTheme.dividerSubtle),

            // ── Request list ─────────────────────────────────────────────────
            Expanded(
              child: AnimatedBuilder(
                animation: widget.session,
                builder: (context, _) {
                  if (widget.groupingEnabled) {
                    return _buildGroupedList(context);
                  } else {
                    return _buildFlatList(context);
                  }
                },
              ),
            ),

            // ── Bottom export bar (selection mode only) ──────────────────────
            if (_isSelectionMode)
              Container(
                decoration: BoxDecoration(
                  color: colors.surfacePrimary,
                  border: Border(
                    top: BorderSide(color: InterceptlyTheme.dividerSubtle),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 12.0),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _selectedIds.isEmpty || _isExporting
                          ? null
                          : _exportSelectedAsPostman,
                      icon: _isExporting
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
                        _isExporting
                            ? 'Exporting…'
                            : 'Export ${_selectedIds.length} to Postman',
                        style: InterceptlyTheme.typography.bodyMediumMedium
                            .copyWith(color: colors.textOnAction),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.actionPrimary,
                        foregroundColor: colors.textOnAction,
                        disabledBackgroundColor:
                            InterceptlyTheme.controlMuted,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              InterceptlyTheme.radius.md),
                        ),
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

  // ── Flat list ───────────────────────────────────────────────────────────────

  Widget _buildFlatList(BuildContext context) {
    final entries = widget.session.getFilteredRecords();

    if (entries.isEmpty) {
      return Center(
        child: Text(
          'No network requests yet.',
          style: InterceptlyTheme.typography.bodyMediumRegular
              .copyWith(color: InterceptlyTheme.textMuted),
        ),
      );
    }

    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: InterceptlyTheme.dividerSubtle),
      itemBuilder: (context, index) {
        final req = entries[index];
        return _buildRequestItem(
          context: context,
          id: req.id,
          method: req.method,
          url: req.url,
          statusCode: req.statusCode,
          durationMs: req.durationMs,
          timestamp: req.timestamp,
          hasError: req.hasError,
          errorType: req.errorType,
          errorMessage: req.errorMessage,
          onTapNavigate: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                RequestDetailPage(entry: req, session: widget.session),
          )),
        );
      },
    );
  }

  // ── Grouped list ────────────────────────────────────────────────────────────

  Widget _buildGroupedList(BuildContext context) {
    final groups = widget.session.getGroupedRecords();

    if (groups.isEmpty) {
      return Center(
        child: Text(
          'No network requests yet.',
          style: InterceptlyTheme.typography.bodyMediumRegular
              .copyWith(color: InterceptlyTheme.textMuted),
        ),
      );
    }

    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, groupIndex) {
        final group = groups[groupIndex];
        final groupIds = group.requests.map((r) => r.id).toList();
        final allGroupSelected =
            groupIds.isNotEmpty &&
            groupIds.every((id) => _selectedIds.contains(id));
        final someGroupSelected =
            !allGroupSelected &&
            groupIds.any((id) => _selectedIds.contains(id));

        return Column(
          children: [
            // ── Domain group header ─────────────────────────────────────────
            if (_isSelectionMode)
              _buildSelectableGroupHeader(
                group: group,
                groupIds: groupIds,
                allSelected: allGroupSelected,
                someSelected: someGroupSelected,
              )
            else
              GestureDetector(
                onTap: () =>
                    widget.session.toggleDomainExpanded(group.domain),
                child: DomainGroupHeader(
                  group: group,
                  onToggleExpand: () =>
                      widget.session.toggleDomainExpanded(group.domain),
                ),
              ),

            // ── Requests in group ───────────────────────────────────────────
            if (group.isExpanded)
              ...group.requests.asMap().entries.map((entry) {
                final record = entry.value;
                final isLast = entry.key == group.requests.length - 1;
                return Column(
                  children: [
                    _buildRequestItem(
                      context: context,
                      id: record.id,
                      method: record.method,
                      url: record.url,
                      statusCode: record.statusCode,
                      durationMs: record.durationMs,
                      timestamp: record.timestamp,
                      hasError: record.hasError,
                      errorType: record.errorType,
                      errorMessage: record.errorMessage,
                      onTapNavigate: () =>
                          Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => RequestDetailPage(
                          entry: record,
                          session: widget.session,
                        ),
                      )),
                    ),
                    if (!isLast)
                      Divider(
                          height: 1,
                          color: InterceptlyTheme.dividerSubtle),
                  ],
                );
              }),

            Divider(height: 1, color: InterceptlyTheme.dividerSubtle),
          ],
        );
      },
    );
  }

  /// Domain header rendered while in selection mode — shows a group
  /// checkbox in the trailing slot and keeps expand/collapse working.
  Widget _buildSelectableGroupHeader({
    required DomainGroup group,
    required List<String> groupIds,
    required bool allSelected,
    required bool someSelected,
  }) {
    final colors = InterceptlyTheme.colors;

    return Container(
      color: InterceptlyTheme.controlMuted,
      child: ListTile(
        leading: GestureDetector(
          onTap: () => widget.session.toggleDomainExpanded(group.domain),
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
          onTap: () => _toggleGroupSelection(groupIds),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: allSelected
                  ? colors.actionPrimary
                  : someSelected
                      ? colors.actionPrimary.withValues(alpha: 0.3)
                      : InterceptlyGlobalColor.transparent,
              borderRadius:
                  BorderRadius.circular(InterceptlyTheme.radius.sm),
              border: Border.all(
                color: allSelected || someSelected
                    ? colors.actionPrimary
                    : InterceptlyTheme.dividerSubtle.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            child: allSelected
                ? Icon(Icons.check,
                    size: 14, color: colors.textOnAction)
                : someSelected
                    ? Icon(Icons.remove,
                        size: 14, color: colors.textOnAction)
                    : null,
          ),
        ),
        onTap: () => widget.session.toggleDomainExpanded(group.domain),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
    );
  }

  // ── Shared request row builder ──────────────────────────────────────────────

  Widget _buildRequestItem({
    required BuildContext context,
    required String id,
    required String method,
    required String url,
    required int statusCode,
    required int durationMs,
    required DateTime timestamp,
    required bool hasError,
    required String? errorType,
    required String? errorMessage,
    required VoidCallback onTapNavigate,
  }) {
    final isPending = statusCode == 0 && !hasError;
    final isErrorWithoutStatus = statusCode == 0 && hasError;
    final shortError = summarizeRequestError(
      errorType: errorType,
      errorMessage: errorMessage,
    );
    final time =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';

    String displayUrl = url;
    if (widget.session.urlDecodeEnabled) {
      try {
        displayUrl = Uri.decodeFull(url);
      } catch (_) {}
    }

    return _RequestLogItem(
      method: method,
      url: displayUrl,
      time: time,
      duration: isPending
          ? 'loading…'
          : isErrorWithoutStatus
              ? shortError
              : '${durationMs}ms',
      status: statusCode,
      hasError: hasError,
      isPending: isPending,
      isSelectionMode: _isSelectionMode,
      isSelected: _selectedIds.contains(id),
      onLongPress: () => _enterSelectionMode(id),
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(id);
          return;
        }
        onTapNavigate();
      },
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

}

// ── Request row widget ────────────────────────────────────────────────────────

class _RequestLogItem extends StatelessWidget {
  const _RequestLogItem({
    required this.method,
    required this.url,
    required this.time,
    required this.duration,
    required this.status,
    required this.hasError,
    required this.isPending,
    required this.onTap,
    required this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
  });

  final String method;
  final String url;
  final String time;
  final String duration;
  final int status;
  final bool hasError;
  final bool isPending;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = InterceptlyTheme.colors;
    final mStyle = InterceptlyTheme.getMethodStyle(method);
    final isErrorWithoutStatus = status == 0 && hasError;
    final sStyle = isErrorWithoutStatus
        ? const StatusStyle(
            bg: InterceptlyTheme.red500,
            text: InterceptlyGlobalColor.white,
          )
        : InterceptlyTheme.getStatusStyle(status);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      hoverColor: InterceptlyTheme.hoverOverlay,
      child: Container(
        color: isSelected
            ? colors.actionPrimary.withValues(alpha: 0.08)
            : null,
        padding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            // ── Checkbox (selection mode only) ──────────────────────────────
            if (isSelectionMode) ...[
              _SelectionCheckbox(
                isSelected: isSelected,
                actionColor: colors.actionPrimary,
                onTap: onTap,
              ),
              const SizedBox(width: 10),
            ],

            // ── Method badge ─────────────────────────────────────────────────
            Container(
              width: 48,
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              decoration: BoxDecoration(
                color: mStyle.bg.withValues(alpha: 0.22),
                border:
                    Border.all(color: mStyle.border.withValues(alpha: 0.8)),
                borderRadius:
                    BorderRadius.circular(InterceptlyTheme.radius.sm + 2),
              ),
              alignment: Alignment.center,
              child: Text(
                method,
                style:
                    InterceptlyTheme.typography.labelSmallMedium.copyWith(
                  color: mStyle.text,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
            ),

            const SizedBox(width: 12),

            // ── URL + time ──────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    url,
                    style: InterceptlyTheme.typography.bodyMediumMedium
                        .copyWith(
                      fontSize: 13,
                      color: colors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$time • $duration',
                    style: InterceptlyTheme.typography.bodyMediumRegular
                        .copyWith(
                      fontSize: 11,
                      color: InterceptlyTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // ── Status badge ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8.0, vertical: 4.0),
              decoration: BoxDecoration(
                color: sStyle.bg,
                borderRadius: BorderRadius.circular(12.0),
              ),
              alignment: Alignment.center,
              child: isPending
                  ? SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(sStyle.text),
                      ),
                    )
                  : Text(
                      isErrorWithoutStatus ? 'ERR' : status.toString(),
                      style: InterceptlyTheme.typography.bodyMediumBold
                          .copyWith(
                        fontSize: 11,
                        color: sStyle.text,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable selection checkbox ───────────────────────────────────────────────

class _SelectionCheckbox extends StatelessWidget {
  const _SelectionCheckbox({
    required this.isSelected,
    required this.actionColor,
    required this.onTap,
  });

  final bool isSelected;
  final Color actionColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: isSelected ? actionColor : InterceptlyGlobalColor.transparent,
          borderRadius:
              BorderRadius.circular(InterceptlyTheme.radius.sm),
          border: Border.all(
            color: isSelected
                ? actionColor
                : InterceptlyTheme.controlMuted,
            width: 1.5,
          ),
        ),
        child: isSelected
            ? Icon(Icons.check,
                size: 14, color: InterceptlyGlobalColor.white)
            : null,
      ),
    );
  }
}
