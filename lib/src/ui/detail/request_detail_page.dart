import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/widgets/interceptly_text_field.dart';

import '../../model/index_entry.dart';
import '../../model/request_record.dart';
import '../../model/request_summary.dart';
import '../../session/inspector_session.dart';
import '../../session/inspector_session_view.dart';
import 'detail_search.dart';
import 'detail_tabs_builder.dart';
import 'replay_handler.dart';
import 'share_handler.dart';

/// Detail screen for an individual captured request/response record.
class RequestDetailPage extends StatefulWidget {
  /// Summary entry selected from the list tab.
  final RequestSummary entry;

  /// Session used to load full detail and replay actions.
  final InspectorSessionView session;

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
  late RequestSummary _currentEntry;
  final TextEditingController _searchController = TextEditingController();
  late Future<RequestRecord> _recordFuture;
  final GlobalKey _fabKey = GlobalKey();

  String _query = '';
  int _currentMatchIndex = 0;

  RequestRecord? _cachedRecord;
  List<DetailMatch> _cachedMatches = const [];

  String? _parsedReqForId;
  dynamic _parsedReq;
  String? _parsedResForId;
  dynamic _parsedRes;

  final Set<int> _visitedTabs = {0};
  int _detailLoadGeneration = 0;
  final Map<DetailSection, GlobalKey> _sectionKeys = {
    for (final s in DetailSection.values) s: GlobalKey(),
  };
  int _scrollNavGeneration = 0;

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
        });
        _parseBodiesAsync(record);
        _recomputeMatchesAsync();
      }
    });
    final isWs = _currentEntry.method == 'WS';
    _tabController = TabController(length: isWs ? 2 : 4, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onSessionChanged() {
    RequestSummary? latest;
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

  bool _entryChanged(RequestSummary prev, RequestSummary next) {
    final prevI = prev as IndexEntry;
    final nextI = next as IndexEntry;
    return prev.statusCode != next.statusCode ||
        prev.durationMs != next.durationMs ||
        prev.responseSizeBytes != next.responseSizeBytes ||
        prev.hasError != next.hasError ||
        prev.errorType != next.errorType ||
        prev.errorMessage != next.errorMessage ||
        prevI.bodyLocation != nextI.bodyLocation ||
        prevI.fileOffset != nextI.fileOffset ||
        prevI.fileLength != nextI.fileLength;
  }

  Future<void> _refreshDetail(RequestSummary entry) async {
    final generation = ++_detailLoadGeneration;
    final future = widget.session.loadDetail(entry);
    _recordFuture = future;
    final record = await future;
    if (!mounted || generation != _detailLoadGeneration) return;
    setState(() {
      _cachedRecord = record;
    });
    _parseBodiesAsync(record);
    _recomputeMatchesAsync();
  }

  void _onTabChanged() {
    final idx = _tabController.index;
    if (!_visitedTabs.contains(idx)) {
      setState(() {
        _visitedTabs.add(idx);
      });
    }
  }

  /// Async recomputation that runs on a background isolate. Falls back to the
  /// synchronous path if the snapshot round-trip fails (defensive — keeps
  /// search functional even if the payload has unusual types).
  ///
  /// Generation counter prevents late-arriving completions from clobbering
  /// the latest query.
  int _matchesGeneration = 0;

  Future<void> _recomputeMatchesAsync() async {
    final record = _cachedRecord;
    if (record == null) {
      _cachedMatches = const [];
      return;
    }
    final isWs = widget.entry.method == 'WS';
    final gen = ++_matchesGeneration;
    List<DetailMatch> next;
    try {
      next = await computeMatchesAsync(record, _query, isWs);
    } catch (_) {
      next = computeMatches(record, _query, isWs, _tryParseJson);
    }
    if (!mounted || gen != _matchesGeneration) return;
    setState(() {
      _cachedMatches = next;
      _currentMatchIndex = 0;
    });
    if (next.isNotEmpty) {
      _scrollToActiveMatch(next[0]);
    }
  }

  void _scrollToActiveMatch(DetailMatch activeMatch) {
    final gen = ++_scrollNavGeneration;

    void executeOuterScroll() {
      if (!mounted || gen != _scrollNavGeneration) return;
      final key = _sectionKeys[activeMatch.section];
      final targetContext = key?.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: 0.05,
        );
      }
    }

    if (_tabController.index != activeMatch.tabIndex) {
      if (_tabController.length > activeMatch.tabIndex) {
        if (!_visitedTabs.contains(activeMatch.tabIndex)) {
          setState(() {
            _visitedTabs.add(activeMatch.tabIndex);
          });
        }
        _tabController.animateTo(activeMatch.tabIndex);
        Future.delayed(const Duration(milliseconds: 320), () {
          if (mounted && gen == _scrollNavGeneration) {
            executeOuterScroll();
          }
        });
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        executeOuterScroll();
      });
    }
  }

  Future<void> _parseBodiesAsync(RequestRecord record) async {
    Future<dynamic> parseOne(String? preview, Uint8List? bytes) async {
      if (bytes != null && bytes.isNotEmpty) {
        if (bytes.length > 50 * 1024) {
          return compute(_decodeBytesToJson, bytes);
        }
        try {
          return jsonDecode(utf8.decode(bytes));
        } catch (_) {
          return _decodeBytesToJson(bytes);
        }
      }

      if (preview == null || preview.isEmpty) return preview;
      if (preview.length > 50 * 1024) {
        return compute(jsonDecodeSafe, preview);
      }
      return jsonDecodeSafe(preview);
    }

    final reqFuture =
        parseOne(record.requestBodyPreview, record.requestBodyBytes);
    final resFuture =
        parseOne(record.responseBodyPreview, record.responseBodyBytes);
    final reqParsed = await reqFuture;
    final resParsed = await resFuture;

    if (!mounted || _cachedRecord?.id != record.id) return;
    setState(() {
      _parsedReqForId = record.id;
      _parsedReq = reqParsed;
      _parsedResForId = record.id;
      _parsedRes = resParsed;
    });
  }

  static dynamic _decodeBytesToJson(Uint8List bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (_) {
      try {
        final slice = bytes.length > 2 * 1024 * 1024
            ? bytes.sublist(0, 2 * 1024 * 1024)
            : bytes;
        final text = utf8.decode(slice, allowMalformed: true);
        return jsonDecodeSafe(text);
      } catch (e) {
        return e.toString();
      }
    }
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
    final record = _cachedRecord;
    if (record != null) {
      if (identical(content, record.requestBodyPreview) &&
          _parsedReqForId == record.id) {
        return _parsedReq;
      }
      if (identical(content, record.responseBodyPreview) &&
          _parsedResForId == record.id) {
        return _parsedRes;
      }
    }
    return jsonDecodeSafe(content);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = widget.session.preferences.themeMode;
    final urlDecodeEnabled = widget.session.preferences.urlDecodeEnabled;

    InterceptlyTheme.bind(
      context: context,
      themeMode: themeMode,
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
    if (urlDecodeEnabled) {
      try {
        displayUrl = Uri.decodeFull(entry.url);
      } catch (_) {}
    }

    final path = Uri.tryParse(displayUrl)?.path ?? displayUrl;

    return Theme(
      data: InterceptlyTheme.themeData(
        context: context,
        themeMode: themeMode,
      ),
      child: Builder(
        builder: (themedContext) => Scaffold(
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
                child: _buildReplayChip(themedContext),
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
                    color: InterceptlyTheme.indigo500,
                  ),
                );
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

              return Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 10.0,
                        ),
                        decoration: BoxDecoration(
                          color: InterceptlyTheme.surface,
                          border: Border(
                            bottom: BorderSide(
                              color: InterceptlyTheme.dividerSubtle,
                            ),
                          ),
                        ),
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
                              _recomputeMatchesAsync();
                            }
                          },
                          onSubmitted: (value) {
                            setState(() {
                              _query = value.trim();
                              _currentMatchIndex = 0;
                            });
                            _recomputeMatchesAsync();
                          },
                        ),
                      ),
                      TabBar(
                        controller: _tabController,
                        indicatorColor: InterceptlyTheme.indigo500,
                        labelColor: InterceptlyTheme.indigo400,
                        unselectedLabelColor: InterceptlyTheme.textQuaternary,
                        dividerColor: InterceptlyGlobalColor.transparent,
                        tabs: isWs
                            ? const [Tab(text: 'Overview'), Tab(text: 'Messages')]
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
                            if (!_visitedTabs.contains(tabIndex)) {
                              _visitedTabs.add(tabIndex);
                            }
                            final tabsBuilder = DetailTabsBuilder(
                              record: record,
                              matches: matches,
                              activeGlobalIndex: activeGlobalIndex,
                              query: _query,
                              urlDecodeEnabled: urlDecodeEnabled,
                              tryParseJson: _tryParseJson,
                              sectionKeys: _sectionKeys,
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
                  ),
                  if (_query.isNotEmpty)
                    Positioned(
                      left: 16.0,
                      bottom: 16.0,
                      child: SafeArea(
                        child: _buildSearchNavigationCapsule(
                          matches: matches,
                          totalMatches: totalMatches,
                          effectiveIndex: effectiveIndex,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          floatingActionButton: FloatingActionButton.extended(
            key: _fabKey,
            heroTag: null,
            onPressed: () => _showShareMenu(themedContext),
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
        ),
      ),
    );
  }

  Widget _buildReplayChip(BuildContext ctx) {
    return Material(
      color: InterceptlyTheme.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showReplayMenu(ctx),
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
    required RequestSummary entry,
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

  void _showShareMenu(BuildContext ctx) {
    final record = _cachedRecord;
    if (record == null) return;

    final shareHandler = ShareHandler(context: ctx, fabKey: _fabKey);
    shareHandler.showShareMenu(record);
  }

  void _showReplayMenu(BuildContext ctx) {
    final record = _cachedRecord;
    if (record == null) return;

    final replayHandler = ReplayHandler(
      context: ctx,
      session: widget.session as InspectorSession,
    );
    replayHandler.showReplayMenu(record);
  }

  Widget _buildSearchNavigationCapsule({
    required List<DetailMatch> matches,
    required int totalMatches,
    required int effectiveIndex,
  }) {
    return Material(
      color: InterceptlyTheme.surface,
      elevation: 6.0,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(24.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24.0),
          border: Border.all(
            color: InterceptlyTheme.dividerSubtle,
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 15,
              color: totalMatches == 0
                  ? InterceptlyTheme.textQuaternary
                  : InterceptlyTheme.indigo500,
            ),
            const SizedBox(width: 6),
            Text(
              totalMatches == 0
                  ? '0 / 0'
                  : '${effectiveIndex + 1} / $totalMatches',
              style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: totalMatches == 0
                    ? InterceptlyTheme.textQuaternary
                    : InterceptlyTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              height: 14,
              width: 1,
              color: InterceptlyTheme.dividerSubtle,
            ),
            const SizedBox(width: 2),
            IconButton(
              icon: Icon(
                Icons.keyboard_arrow_up,
                size: 18,
                color: totalMatches == 0
                    ? InterceptlyTheme.textQuaternary
                    : InterceptlyTheme.textSecondary,
              ),
              tooltip: 'Previous match',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              splashRadius: 16,
              onPressed: totalMatches == 0
                  ? null
                  : () {
                      final newIndex = (_currentMatchIndex - 1) % totalMatches;
                      final normalized =
                          (newIndex + totalMatches) % totalMatches;
                      setState(() {
                        _currentMatchIndex = normalized;
                      });
                      _scrollToActiveMatch(matches[normalized]);
                    },
            ),
            IconButton(
              icon: Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: totalMatches == 0
                    ? InterceptlyTheme.textQuaternary
                    : InterceptlyTheme.textSecondary,
              ),
              tooltip: 'Next match',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              splashRadius: 16,
              onPressed: totalMatches == 0
                  ? null
                  : () {
                      final newIndex = (_currentMatchIndex + 1) % totalMatches;
                      final normalized =
                          (newIndex + totalMatches) % totalMatches;
                      setState(() {
                        _currentMatchIndex = normalized;
                      });
                      _scrollToActiveMatch(matches[normalized]);
                    },
            ),
            const SizedBox(width: 2),
            IconButton(
              icon: const Icon(
                Icons.close,
                size: 15,
                color: InterceptlyTheme.textMuted,
              ),
              tooltip: 'Close search',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              splashRadius: 16,
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _query = '';
                  _currentMatchIndex = 0;
                });
                _recomputeMatchesAsync();
              },
            ),
          ],
        ),
      ),
    );
  }
}
