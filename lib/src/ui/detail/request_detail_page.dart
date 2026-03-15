import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/widgets/interceptly_text_field.dart';

import '../../model/index_entry.dart';
import '../../model/request_record.dart';
import '../../storage/inspector_session.dart';
import '_detail_search.dart';
import '_detail_tabs.dart';
import '_replay_handler.dart';
import '_share_handler.dart';

/// Detail screen for an individual captured request/response record.
class RequestDetailPage extends StatefulWidget {
  /// Indexed entry selected from the list tab.
  final IndexEntry entry;

  /// Session used to load full detail and replay actions.
  final InspectorSession session;

  /// Creates a detail page for [entry] using [session].
  const RequestDetailPage({
    super.key,
    required this.entry,
    required this.session,
  });

  @override
  State<RequestDetailPage> createState() => _RequestDetailPageState();
}

class _RequestDetailPageState extends State<RequestDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late IndexEntry _currentEntry;
  final TextEditingController _searchController = TextEditingController();
  late Future<RequestRecord> _recordFuture;
  final GlobalKey _fabKey = GlobalKey();

  String _query = '';
  int _currentMatchIndex = 0;

  // Cached data
  RequestRecord? _cachedRecord;
  List<DetailMatch> _cachedMatches = const [];
  String _cachedQuery = '';

  // Track which tabs have been visited (for lazy building)
  final Set<int> _visitedTabs = {0};
  int _detailLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _currentEntry = widget.entry;
    _recordFuture = widget.session.loadDetail(_currentEntry);
    widget.session.addListener(_onSessionChanged);
    _recordFuture.then((record) {
      if (mounted) {
        setState(() {
          _cachedRecord = record;
          _recomputeMatches();
        });
        // Pre-build remaining tabs on the next frame after initial render
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              for (int i = 0; i < _tabController.length; i++) {
                _visitedTabs.add(i);
              }
            });
          }
        });
      }
    });
    final isWs = _currentEntry.method == 'WS';
    _tabController = TabController(length: isWs ? 2 : 4, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onSessionChanged() {
    IndexEntry? latest;
    for (final entry in widget.session.entries) {
      if (entry.id == _currentEntry.id) {
        latest = entry;
        break;
      }
    }
    if (latest == null) return;

    if (_entryChanged(_currentEntry, latest)) {
      _currentEntry = latest;
      _refreshDetail(latest);
      if (mounted) {
        setState(() {});
      }
    }
  }

  bool _entryChanged(IndexEntry prev, IndexEntry next) {
    return prev.statusCode != next.statusCode ||
        prev.durationMs != next.durationMs ||
        prev.responseSizeBytes != next.responseSizeBytes ||
        prev.hasError != next.hasError ||
        prev.errorType != next.errorType ||
        prev.errorMessage != next.errorMessage ||
        prev.bodyLocation != next.bodyLocation ||
        prev.fileOffset != next.fileOffset ||
        prev.fileLength != next.fileLength;
  }

  Future<void> _refreshDetail(IndexEntry entry) async {
    final generation = ++_detailLoadGeneration;
    final future = widget.session.loadDetail(entry);
    _recordFuture = future;
    final record = await future;
    if (!mounted || generation != _detailLoadGeneration) return;
    setState(() {
      _cachedRecord = record;
      _recomputeMatches();
    });
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      final idx = _tabController.index;
      if (!_visitedTabs.contains(idx)) {
        setState(() {
          _visitedTabs.add(idx);
        });
      }
    }
  }

  void _recomputeMatches() {
    final record = _cachedRecord;
    if (record == null) {
      _cachedMatches = const [];
      return;
    }
    final isWs = widget.entry.method == 'WS';
    _cachedMatches = computeMatches(record, _query, isWs, _tryParseJson);
    _cachedQuery = _query;
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  dynamic _tryParseJson(String? content) {
    if (content == null || content.isEmpty) return content;
    try {
      return jsonDecode(content);
    } catch (_) {
      return content;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        InterceptlyTheme.bind(
          context: context,
          themeMode: widget.session.themeMode,
        );

        final entry = _currentEntry;
        final isWs = entry.method == 'WS';
        final isPending = entry.statusCode == 0 && !entry.hasError;
        final isErrorWithoutStatus = entry.statusCode == 0 && entry.hasError;
        final sStyle = isErrorWithoutStatus
            ? const StatusStyle(
                bg: InterceptlyTheme.red500,
                text: InterceptlyGlobalColor.white,
              )
            : InterceptlyTheme.getStatusStyle(entry.statusCode);

        String displayUrl = entry.url;
        if (widget.session.urlDecodeEnabled) {
          try {
            displayUrl = Uri.decodeFull(entry.url);
          } catch (_) {}
        }

        final path = Uri.tryParse(displayUrl)?.path ?? displayUrl;

        return Scaffold(
          backgroundColor: InterceptlyTheme.surface,
          appBar: AppBar(
            backgroundColor: InterceptlyTheme.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            iconTheme: IconThemeData(color: InterceptlyTheme.textSecondary),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              path,
              style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                fontSize: 14,
                color: InterceptlyTheme.textPrimary,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: _buildReplayChip(),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: _buildStatusChip(
                  entry: entry,
                  isPending: isPending,
                  isErrorWithoutStatus: isErrorWithoutStatus,
                  statusStyle: sStyle,
                ),
              ),
            ],
          ),
          body: Builder(
            builder: (context) {
              final record = _cachedRecord;
              if (record == null) {
                return const Center(
                  child: CircularProgressIndicator(
                      color: InterceptlyTheme.indigo500),
                );
              }

              if (_cachedQuery != _query) {
                _recomputeMatches();
              }

              final matches = _cachedMatches;
              final totalMatches = matches.length;

              int effectiveIndex = _currentMatchIndex;
              if (totalMatches > 0) {
                effectiveIndex %= totalMatches;
                if (effectiveIndex < 0) {
                  effectiveIndex += totalMatches;
                }
              } else {
                effectiveIndex = 0;
              }

              final activeGlobalIndex =
                  totalMatches == 0 ? null : effectiveIndex;
              final activeMatch =
                  totalMatches == 0 ? null : matches[effectiveIndex];

              if (activeMatch != null &&
                  _tabController.index != activeMatch.tabIndex &&
                  _tabController.length > activeMatch.tabIndex) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _tabController.animateTo(activeMatch.tabIndex);
                  }
                });
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 12.0),
                    decoration: BoxDecoration(
                      color: InterceptlyTheme.surface,
                      border: Border(
                          bottom: BorderSide(
                              color: InterceptlyTheme.dividerSubtle)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InterceptlySearchField(
                            controller: _searchController,
                            hintText: 'Search in details...',
                            textInputAction: TextInputAction.search,
                            onChanged: (value) {
                              if (value.trim().isEmpty && _query.isNotEmpty) {
                                setState(() {
                                  _query = '';
                                  _currentMatchIndex = 0;
                                });
                              }
                            },
                            onSubmitted: (value) {
                              setState(() {
                                _query = value.trim();
                                _currentMatchIndex = 0;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          totalMatches == 0
                              ? '0 / 0'
                              : '${effectiveIndex + 1} / $totalMatches',
                          style: InterceptlyTheme.typography.bodyMediumRegular
                              .copyWith(
                            fontSize: 12,
                            color: InterceptlyTheme.textMuted,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.keyboard_arrow_up,
                            size: 20,
                            color: InterceptlyTheme.textMuted,
                          ),
                          tooltip: 'Previous match',
                          onPressed: totalMatches == 0
                              ? null
                              : () {
                                  setState(() {
                                    _currentMatchIndex--;
                                  });
                                },
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            size: 20,
                            color: InterceptlyTheme.textMuted,
                          ),
                          tooltip: 'Next match',
                          onPressed: totalMatches == 0
                              ? null
                              : () {
                                  setState(() {
                                    _currentMatchIndex++;
                                  });
                                },
                        ),
                      ],
                    ),
                  ),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: InterceptlyTheme.indigo500,
                    labelColor: InterceptlyTheme.indigo400,
                    unselectedLabelColor: InterceptlyTheme.textQuaternary,
                    dividerColor: InterceptlyGlobalColor.transparent,
                    tabs: isWs
                        ? const [
                            Tab(text: 'Overview'),
                            Tab(text: 'Messages'),
                          ]
                        : const [
                            Tab(text: 'Overview'),
                            Tab(text: 'Request'),
                            Tab(text: 'Response'),
                            Tab(text: 'Error'),
                          ],
                  ),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _tabController,
                      builder: (context, _) {
                        final tabIndex = _tabController.index;
                        final tabsBuilder = DetailTabsBuilder(
                          record: record,
                          matches: matches,
                          activeGlobalIndex: activeGlobalIndex,
                          query: _query,
                          urlDecodeEnabled: widget.session.urlDecodeEnabled,
                          tryParseJson: _tryParseJson,
                        );
                        return IndexedStack(
                          index: tabIndex,
                          children: isWs
                              ? [
                                  _visitedTabs.contains(0)
                                      ? tabsBuilder.buildOverviewTab()
                                      : const SizedBox.shrink(),
                                  _visitedTabs.contains(1)
                                      ? tabsBuilder.buildMessagesTab()
                                      : const SizedBox.shrink(),
                                ]
                              : [
                                  _visitedTabs.contains(0)
                                      ? tabsBuilder.buildOverviewTab()
                                      : const SizedBox.shrink(),
                                  _visitedTabs.contains(1)
                                      ? tabsBuilder.buildRequestTab()
                                      : const SizedBox.shrink(),
                                  _visitedTabs.contains(2)
                                      ? tabsBuilder.buildResponseTab()
                                      : const SizedBox.shrink(),
                                  _visitedTabs.contains(3)
                                      ? tabsBuilder.buildErrorTab()
                                      : const SizedBox.shrink(),
                                ],
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          floatingActionButton: FloatingActionButton.extended(
            key: _fabKey,
            heroTag: null,
            onPressed: _showShareMenu,
            backgroundColor: InterceptlyTheme.indigo500,
            foregroundColor: InterceptlyGlobalColor.white,
            icon: const Icon(Icons.share, size: 18),
            label: Text(
              'Share',
              style: InterceptlyTheme.typography.bodyMediumMedium.copyWith(
                color: InterceptlyGlobalColor.white,
                fontSize: 13,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReplayChip() {
    return Material(
      color: InterceptlyTheme.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _showReplayMenu,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.play_arrow_rounded,
                size: 16,
                color: InterceptlyTheme.indigo400,
              ),
              const SizedBox(width: 4),
              Text(
                'Replay',
                style: InterceptlyTheme.typography.bodyMediumMedium.copyWith(
                  fontSize: 12,
                  color: InterceptlyTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip({
    required IndexEntry entry,
    required bool isPending,
    required bool isErrorWithoutStatus,
    required StatusStyle statusStyle,
  }) {
    final label = isPending
        ? 'PENDING'
        : isErrorWithoutStatus
            ? 'ERR'
            : '${entry.statusCode}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: statusStyle.bg.withValues(alpha: 0.18),
        border: Border.all(color: statusStyle.bg.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPending)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                valueColor: AlwaysStoppedAnimation<Color>(statusStyle.bg),
              ),
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusStyle.bg,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
              color: InterceptlyTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _showShareMenu() {
    final record = _cachedRecord;
    if (record == null) return;

    final shareHandler = ShareHandler(
      context: context,
      fabKey: _fabKey,
    );
    shareHandler.showShareMenu(record);
  }

  void _showReplayMenu() {
    final record = _cachedRecord;
    if (record == null) return;

    final replayHandler = ReplayHandler(
      context: context,
      session: widget.session,
    );
    replayHandler.showReplayMenu(record);
  }
}
