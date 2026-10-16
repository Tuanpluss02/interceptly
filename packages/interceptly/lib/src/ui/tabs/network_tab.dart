import 'dart:async';

import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';
import 'package:interceptly/src/ui/detail/share_handler.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/tabs/rest_log_item.dart';
import 'package:interceptly/src/ui/widgets/domain_group_header.dart';
import 'package:interceptly/src/ui/widgets/error_summary.dart';
import 'package:interceptly/src/ui/widgets/interceptly_text_field.dart';
import 'package:interceptly/src/ui/widgets/toast_notification.dart';

import '../../model/domain_group.dart';
import '../../model/request_record.dart';
import '../../model/request_summary.dart';
import '../../session/inspector_session_view.dart';
import '../widgets/filter_badge.dart';
import 'quick_filter_bar.dart';

part 'network_tab_widgets.dart';

/// REST-only traffic list with search, quick filters, grouping and export.
class NetworkTab extends StatefulWidget {
  /// Creates a REST-only list bound to [session].
  const NetworkTab({
    super.key,
    required this.session,
    this.groupingEnabled = false,
    this.onShowFilterPanel,
  });

  /// Session providing filtered REST entries and search scopes.
  final InspectorSessionView session;

  /// Whether entries render grouped by domain.
  final bool groupingEnabled;

  /// Opens the full filter panel when set.
  final VoidCallback? onShowFilterPanel;

  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<NetworkTab> {
  late TextEditingController _searchController;

  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  bool _isExporting = false;
  final Map<String, String> _displayUrlCache = {};
  bool? _cachedUrlDecodeSetting;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.session.masterQuery ?? '',
    );
  }

  @override
  void dispose() {
    _displayUrlCache.clear();
    _searchController.dispose();
    super.dispose();
  }

  /// Display URL honoring the url-decode preference with per-row caching.
  String _getDisplayUrl(RequestSummary entry) {
    final decodeEnabled = widget.session.preferences.urlDecodeEnabled;
    if (_cachedUrlDecodeSetting != decodeEnabled) {
      _displayUrlCache.clear();
      _cachedUrlDecodeSetting = decodeEnabled;
    }
    final cached = _displayUrlCache[entry.id];
    if (cached != null) return cached;

    String displayUrl = entry.url;
    if (decodeEnabled) {
      try {
        displayUrl = Uri.decodeFull(entry.url);
      } catch (_) {}
    }
    _displayUrlCache[entry.id] = displayUrl;
    return displayUrl;
  }

  /// Enters multi-select mode with [id] pre-selected.
  void _enterSelectionMode(String id) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(id);
    });
  }

  /// Leaves multi-select mode and clears the selection.
  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  /// Toggles selection of a single row, exiting mode when empty.
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

  /// Toggles selection of every row in a domain group.
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

  /// Exports selected rows to Postman in chunks of ten.
  Future<void> _exportSelectedAsPostman() async {
    if (_selectedIds.isEmpty || _isExporting) return;
    setState(() => _isExporting = true);

    try {
      final allEntries = widget.session.entries;
      final selectedEntries =
          allEntries.where((e) => _selectedIds.contains(e.id)).toList();

      final List<RequestRecord> records = [];
      for (var i = 0; i < selectedEntries.length; i += 10) {
        final end =
            (i + 10 < selectedEntries.length) ? i + 10 : selectedEntries.length;
        final chunk = selectedEntries.sublist(i, end);
        final chunkRecords = await Future.wait(
          chunk.map((entry) => widget.session.loadDetailById(entry.id)),
        );
        records.addAll(chunkRecords);
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
    final queryText = widget.session.masterQuery ?? '';
    if (_searchController.text != queryText) {
      _searchController.value = TextEditingValue(
        text: queryText,
        selection: TextSelection.collapsed(offset: queryText.length),
      );
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
            if (_isSelectionMode)
              _SelectionTopBar(
                selectedCount: _selectedIds.length,
                colors: colors,
                onCancel: _exitSelectionMode,
              )
            else ...[
              ListenableBuilder(
                listenable: widget.session,
                builder: (context, _) => _SearchFilterBar(
                  controller: _searchController,
                  activeFiltersCount: widget.session.filter.activeFilterCount,
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
              ),
              QuickFilterBar(session: widget.session),
            ],
            Divider(height: 1, color: InterceptlyTheme.dividerSubtle),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.session,
                builder: (context, _) => widget.groupingEnabled
                    ? _buildGroupedList(context)
                    : _buildFlatList(context),
              ),
            ),
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

  /// Drops realtime connections so only REST exchanges render.
  List<RequestSummary> _restOnly(List<RequestSummary> list) {
    return list.where((e) => !e.isRealtime).toList();
  }

  /// Empty-state copy for the REST-only list.
  String get _emptyMessage => 'No network requests yet.';

  /// Flat newest-first list of REST rows.
  Widget _buildFlatList(BuildContext context) {
    final entries = _restOnly(widget.session.entries);

    if (entries.isEmpty) {
      return Center(
        child: Text(
          _emptyMessage,
          style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
            color: InterceptlyTheme.textMuted,
          ),
        ),
      );
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom + 88;

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(12, 10, 12, bottomInset),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final req = entries[index];
        return KeyedSubtree(
          key: ValueKey(req.id),
          child: _buildRequestItem(
            context: context,
            entry: req,
            onTapNavigate: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RequestDetailPage(
                  entry: req,
                  session: widget.session,
                  initialQuery: widget.session.masterQuery,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Domain-grouped list of REST rows with expandable headers.
  Widget _buildGroupedList(BuildContext context) {
    final rawGroups = widget.session.getGroupedRecords();
    final groups = <DomainGroup>[];
    for (final g in rawGroups) {
      final restRequests = _restOnly(g.requests);
      if (restRequests.isNotEmpty) {
        groups.add(DomainGroup(
          domain: g.domain,
          requests: restRequests,
          isExpanded: g.isExpanded,
        ));
      }
    }

    if (groups.isEmpty) {
      return Center(
        child: Text(
          _emptyMessage,
          style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
            color: InterceptlyTheme.textMuted,
          ),
        ),
      );
    }

    final flatItems = <_GroupedItem>[];
    for (final group in groups) {
      final groupIds = group.requests.map((r) => r.id).toList();
      final allGroupSelected = groupIds.isNotEmpty &&
          groupIds.every((id) => _selectedIds.contains(id));
      final someGroupSelected =
          !allGroupSelected && groupIds.any((id) => _selectedIds.contains(id));

      flatItems.add(_GroupHeaderItem(
        group: group,
        groupIds: groupIds,
        allSelected: allGroupSelected,
        someSelected: someGroupSelected,
      ));

      if (group.isExpanded) {
        for (var i = 0; i < group.requests.length; i++) {
          flatItems.add(_GroupRequestItem(
            entry: group.requests[i],
            isLastInGroup: i == group.requests.length - 1,
          ));
        }
      }

      flatItems.add(const _GroupDividerItem());
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom + 88;

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(0, 10, 0, bottomInset),
      itemCount: flatItems.length,
      itemBuilder: (context, index) {
        final item = flatItems[index];
        switch (item) {
          case _GroupHeaderItem(
              :final group,
              :final groupIds,
              :final allSelected,
              :final someSelected
            ):
            if (_isSelectionMode) {
              return KeyedSubtree(
                key: ValueKey('group_header_${group.domain}'),
                child: _SelectableGroupHeader(
                  group: group,
                  groupIds: groupIds,
                  allSelected: allSelected,
                  someSelected: someSelected,
                  onToggleExpand: () =>
                      widget.session.toggleDomainExpanded(group.domain),
                  onToggleGroupSelection: _toggleGroupSelection,
                ),
              );
            }
            return KeyedSubtree(
              key: ValueKey('group_header_${group.domain}'),
              child: GestureDetector(
                onTap: () => widget.session.toggleDomainExpanded(group.domain),
                child: DomainGroupHeader(
                  group: group,
                  onToggleExpand: () =>
                      widget.session.toggleDomainExpanded(group.domain),
                ),
              ),
            );
          case _GroupRequestItem(:final entry, :final isLastInGroup):
            return Padding(
              key: ValueKey(entry.id),
              padding:
                  EdgeInsets.fromLTRB(14, 0, 14, isLastInGroup ? 10.0 : 8.0),
              child: _buildRequestItem(
                context: context,
                entry: entry,
                onTapNavigate: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RequestDetailPage(
                      entry: entry,
                      session: widget.session,
                      initialQuery: widget.session.masterQuery,
                    ),
                  ),
                ),
              ),
            );
          case _GroupDividerItem():
            return Divider(height: 1, color: InterceptlyTheme.dividerSubtle);
        }
      },
    );
  }

  /// Single REST row with status, highlight, scope badges and selection.
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
    final String durationText;
    if (isPending) {
      durationText = 'loading…';
    } else if (isErrorWithoutStatus) {
      durationText = shortError;
    } else {
      durationText = '${entry.durationMs}ms';
    }

    final time =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}';

    final displayUrl = _getDisplayUrl(entry);

    final activeQuery = widget.session.masterQuery;
    final scopes = activeQuery != null && activeQuery.isNotEmpty
        ? widget.session.getSearchScopes(entry.id)
        : null;

    return RestLogItem(
      method: entry.method,
      url: displayUrl,
      time: time,
      duration: durationText,
      status: entry.statusCode,
      hasError: entry.hasError,
      isPending: isPending,
      responseSizeBytes: entry.responseSizeBytes,
      isSelectionMode: _isSelectionMode,
      isSelected: _selectedIds.contains(entry.id),
      searchScopes: scopes,
      highlightQuery: activeQuery,
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

/// Flattened node for the grouped list builder.
sealed class _GroupedItem {
  const _GroupedItem();
}

/// Expandable domain header node.
final class _GroupHeaderItem extends _GroupedItem {
  _GroupHeaderItem({
    required this.group,
    required this.groupIds,
    required this.allSelected,
    required this.someSelected,
  });

  final DomainGroup group;
  final List<String> groupIds;
  final bool allSelected;
  final bool someSelected;
}

/// Single request row node inside an expanded group.
final class _GroupRequestItem extends _GroupedItem {
  _GroupRequestItem({
    required this.entry,
    required this.isLastInGroup,
  });

  final RequestSummary entry;
  final bool isLastInGroup;
}

/// Hairline divider node between groups.
final class _GroupDividerItem extends _GroupedItem {
  const _GroupDividerItem();
}
