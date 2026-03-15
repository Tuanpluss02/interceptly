import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

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
    final entry = _currentEntry;
    final isWs = entry.method == 'WS';
    final isPending = entry.statusCode == 0 && !entry.hasError;
    final isErrorWithoutStatus = entry.statusCode == 0 && entry.hasError;
    final sStyle = isErrorWithoutStatus
        ? const StatusStyle(bg: InterceptlyTheme.red500, text: Colors.white)
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
        iconTheme: const IconThemeData(color: InterceptlyTheme.textSecondary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          path,
          style: const TextStyle(
            fontFamily: InterceptlyTheme.fontFamily,
            package: InterceptlyTheme.fontPackage,
            fontSize: 14,
            color: InterceptlyTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Replay request',
            icon:
                const Icon(Icons.play_arrow, color: InterceptlyTheme.indigo400),
            onPressed: _showReplayMenu,
          ),
          Container(
            margin: const EdgeInsets.only(right: 16.0),
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: sStyle.bg,
              borderRadius: BorderRadius.circular(4.0),
            ),
            alignment: Alignment.center,
            child: isPending
                ? SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      valueColor: AlwaysStoppedAnimation<Color>(sStyle.text),
                    ),
                  )
                : Text(
                    isErrorWithoutStatus
                        ? 'ERR'
                        : '${entry.statusCode} ${entry.statusCode == 200 ? 'OK' : ''}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: sStyle.text,
                    ),
                  ),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          final record = _cachedRecord;
          if (record == null) {
            return const Center(
              child:
                  CircularProgressIndicator(color: InterceptlyTheme.indigo500),
            );
          }

          // Recompute matches only if query changed
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

          final activeGlobalIndex = totalMatches == 0 ? null : effectiveIndex;
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
              // Detail Search Bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                decoration: BoxDecoration(
                  color: InterceptlyTheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (value) {
                          setState(() {
                            _query = value.trim();
                            _currentMatchIndex = 0;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search in details...',
                          hintStyle: const TextStyle(
                            color: InterceptlyTheme.textMuted,
                            fontSize: 14,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: InterceptlyTheme.textMuted,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: InterceptlyTheme.surfaceContainer,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12.0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30.0),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30.0),
                            borderSide: const BorderSide(
                              color: InterceptlyTheme.indigo500,
                              width: 1.0,
                            ),
                          ),
                        ),
                        style: const TextStyle(
                          color: InterceptlyTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      totalMatches == 0
                          ? '0 / 0'
                          : '${effectiveIndex + 1} / $totalMatches',
                      style: const TextStyle(
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
              // TabBar
              TabBar(
                controller: _tabController,
                indicatorColor: InterceptlyTheme.indigo500,
                labelColor: InterceptlyTheme.indigo400,
                unselectedLabelColor: InterceptlyTheme.textQuaternary,
                dividerColor: Colors.transparent,
                tabs: isWs
                    ? const [
                        Tab(text: 'Overview'),
                        Tab(text: 'Messages'),
                      ]
                    : const [
                        Tab(text: 'Overview'),
                        Tab(text: 'Request'),
                        Tab(text: 'Response'),
                        Tab(text: 'Messages'),
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
      floatingActionButton: FloatingActionButton(
        key: _fabKey,
        heroTag: null,
        onPressed: _showShareMenu,
        backgroundColor: InterceptlyTheme.indigo500,
        child: const Icon(Icons.share),
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
