import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';
import 'package:interceptly/src/ui/detail/share_handler.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/tabs/request_log_item.dart';
import 'package:interceptly/src/ui/widgets/domain_group_header.dart';
import 'package:interceptly/src/ui/widgets/error_summary.dart';
import 'package:interceptly/src/ui/widgets/interceptly_text_field.dart';
import 'package:interceptly/src/ui/widgets/toast_notification.dart';

import '../../model/domain_group.dart';
import '../../model/request_record.dart';
import '../../model/request_summary.dart';
import '../../session/inspector_session_view.dart';

part 'network_tab_widgets.dart';

class NetworkTab extends StatefulWidget {
  const NetworkTab({
    super.key,
    required this.session,
    this.groupingEnabled = false,
    this.onShowFilterPanel,
  });

  final InspectorSessionView session;
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
      final allEntries = widget.session.entries;
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
            // ── Top bar ──────────────────────────────────────────────────────
            if (_isSelectionMode)
              _SelectionTopBar(
                selectedCount: _selectedIds.length,
                colors: colors,
                onCancel: _exitSelectionMode,
              )
            else
              _SearchFilterBar(
                controller: _searchController,
                onChanged: (value) {
                  final q = value.trim();
                  if (q.isEmpty) {
                    widget.session.cancelMasterSearch();
                  } else {
                    widget.session.startMasterSearch(q);
                  }
                },
                onShowFilter: widget.onShowFilterPanel,
              ),

            Divider(height: 1, color: InterceptlyTheme.dividerSubtle),

            // ── Request list ─────────────────────────────────────────────────
            Expanded(
              child: AnimatedBuilder(
                animation: widget.session,
                builder: (context, _) => widget.groupingEnabled
                    ? _buildGroupedList(context)
                    : _buildFlatList(context),
              ),
            ),

            // ── Bottom export bar (selection mode only) ──────────────────────
            if (_isSelectionMode)
              _ExportBar(
                selectedCount: _selectedIds.length,
                isExporting: _isExporting,
                colors: colors,
                onExport: _exportSelectedAsPostman,
              ),
          ],
        ),
      ),
    );
  }

  // ── Flat list ───────────────────────────────────────────────────────────────

  Widget _buildFlatList(BuildContext context) {
    final entries = widget.session.entries;

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
          entry: req,
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
        final allGroupSelected = groupIds.isNotEmpty &&
            groupIds.every((id) => _selectedIds.contains(id));
        final someGroupSelected = !allGroupSelected &&
            groupIds.any((id) => _selectedIds.contains(id));

        return Column(
          children: [
            if (_isSelectionMode)
              _SelectableGroupHeader(
                group: group,
                groupIds: groupIds,
                allSelected: allGroupSelected,
                someSelected: someGroupSelected,
                onToggleExpand: () =>
                    widget.session.toggleDomainExpanded(group.domain),
                onToggleGroupSelection: _toggleGroupSelection,
              )
            else
              GestureDetector(
                onTap: () => widget.session.toggleDomainExpanded(group.domain),
                child: DomainGroupHeader(
                  group: group,
                  onToggleExpand: () =>
                      widget.session.toggleDomainExpanded(group.domain),
                ),
              ),

            if (group.isExpanded)
              ...group.requests.asMap().entries.map((entry) {
                final record = entry.value;
                final isLast = entry.key == group.requests.length - 1;
                return Column(
                  children: [
                    _buildRequestItem(
                      context: context,
                      entry: record,
                      onTapNavigate: () =>
                          Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => RequestDetailPage(
                          entry: record,
                          session: widget.session,
                        ),
                      )),
                    ),
                    if (!isLast)
                      Divider(height: 1, color: InterceptlyTheme.dividerSubtle),
                  ],
                );
              }),

            Divider(height: 1, color: InterceptlyTheme.dividerSubtle),
          ],
        );
      },
    );
  }

  // ── Request row ─────────────────────────────────────────────────────────────

  Widget _buildRequestItem({
    required BuildContext context,
    required RequestSummary entry,
    required VoidCallback onTapNavigate,
  }) {
    final isPending = entry.statusCode == 0 && !entry.hasError;
    final isErrorWithoutStatus = entry.statusCode == 0 && entry.hasError;
    final shortError = summarizeRequestError(
      errorType: entry.errorType,
      errorMessage: entry.errorMessage,
    );
    final time =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}';

    String displayUrl = entry.url;
    if (widget.session.preferences.urlDecodeEnabled) {
      try {
        displayUrl = Uri.decodeFull(entry.url);
      } catch (_) {}
    }

    return RequestLogItem(
      method: entry.method,
      url: displayUrl,
      time: time,
      duration: isPending
          ? 'loading…'
          : isErrorWithoutStatus
              ? shortError
              : '${entry.durationMs}ms',
      status: entry.statusCode,
      hasError: entry.hasError,
      isPending: isPending,
      isSelectionMode: _isSelectionMode,
      isSelected: _selectedIds.contains(entry.id),
      onLongPress: () => _enterSelectionMode(entry.id),
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(entry.id);
          return;
        }
        onTapNavigate();
      },
    );
  }
}

