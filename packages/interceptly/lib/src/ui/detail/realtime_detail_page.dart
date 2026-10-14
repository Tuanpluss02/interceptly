import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/format.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

import '../../model/index_entry.dart';
import '../../model/realtime_frame.dart';
import '../../model/request_record.dart';
import '../../model/request_summary.dart';
import '../../session/inspector_session_view.dart';
import 'realtime_messages_tab.dart';

/// Detail screen dedicated to inspect Realtime (WebSocket, SSE, Socket.IO) connections.
class RealtimeDetailPage extends StatefulWidget {
  /// The realtime connection summary entry.
  final RequestSummary entry;

  /// The inspector session tracking connection traffic and frames.
  final InspectorSessionView session;

  /// Optional time provider for deterministic testing of live duration ticking.
  @visibleForTesting
  final DateTime Function()? nowProvider;

  /// Creates a detail page for a realtime connection.
  const RealtimeDetailPage({
    super.key,
    required this.entry,
    required this.session,
    @visibleForTesting this.nowProvider,
  });

  @override
  State<RealtimeDetailPage> createState() => _RealtimeDetailPageState();
}

class _RealtimeDetailPageState extends State<RealtimeDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late RequestSummary _currentEntry;
  late Future<RequestRecord> _recordFuture;
  RequestRecord? _cachedRecord;
  Timer? _liveTicker;

  @override
  void initState() {
    super.initState();
    _currentEntry = widget.entry;
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    _recordFuture = _loadDetailForEntry(_currentEntry);
    widget.session.addListener(_onSessionChanged);
    _recordFuture.then((record) {
      if (mounted) {
        setState(() {
          _cachedRecord = record;
        });
      }
    });
    _updateLiveTicker();
  }

  @override
  void didUpdateWidget(covariant RealtimeDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session != oldWidget.session) {
      oldWidget.session.removeListener(_onSessionChanged);
      widget.session.addListener(_onSessionChanged);
    }
    if (widget.entry.id != oldWidget.entry.id ||
        widget.entry.statusCode != oldWidget.entry.statusCode ||
        widget.entry.hasError != oldWidget.entry.hasError) {
      _currentEntry = widget.entry;
      _refreshDetail(_currentEntry);
      _updateLiveTicker();
    }
  }

  @override
  void dispose() {
    _liveTicker?.cancel();
    _liveTicker = null;
    widget.session.removeListener(_onSessionChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _updateLiveTicker() {
    final isLive = _currentEntry.isRealtime &&
        _currentEntry.statusCode == 0 &&
        !_currentEntry.hasError;
    if (isLive) {
      _liveTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _liveTicker?.cancel();
      _liveTicker = null;
    }
  }

  Future<RequestRecord> _loadDetailForEntry(RequestSummary entry) async {
    try {
      return await widget.session.loadDetailById(entry.id);
    } catch (_) {
      return await widget.session.loadDetail(entry);
    }
  }

  void _onSessionChanged() {
    final latest = widget.session.byId(_currentEntry.id);
    if (latest == null) return;

    if (_entryChanged(_currentEntry, latest)) {
      _currentEntry = latest;
      _updateLiveTicker();
      _refreshDetail(latest);
      if (mounted) setState(() {});
    }
  }

  bool _entryChanged(RequestSummary prev, RequestSummary next) {
    if (prev.statusCode != next.statusCode ||
        prev.durationMs != next.durationMs ||
        prev.responseSizeBytes != next.responseSizeBytes ||
        prev.hasError != next.hasError ||
        prev.errorType != next.errorType ||
        prev.errorMessage != next.errorMessage) {
      return true;
    }
    if (prev is IndexEntry && next is IndexEntry) {
      return prev.bodyLocation != next.bodyLocation ||
          prev.fileOffset != next.fileOffset ||
          prev.fileLength != next.fileLength;
    }
    return false;
  }

  Future<void> _refreshDetail(RequestSummary entry) async {
    final future = _loadDetailForEntry(entry);
    _recordFuture = future;
    final record = await future;
    if (!mounted) return;
    setState(() {
      _cachedRecord = record;
    });
  }

  ({String path, String host}) _splitUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasAuthority) {
      final pathWithQuery =
          uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
      final path = pathWithQuery.isEmpty ? '/' : pathWithQuery;
      return (path: path, host: uri.host);
    }
    return (path: url, host: '');
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = widget.session.preferences.themeMode;
    InterceptlyTheme.bind(
      context: context,
      themeMode: themeMode,
    );
    final colors = InterceptlyTheme.colorsOf(context);
    final themedData = InterceptlyTheme.themeData(
      context: context,
      themeMode: themeMode,
    );
    final entry = _currentEntry;
    final (:path, :host) = _splitUrl(entry.url);
    final isPending = entry.statusCode == 0 && !entry.hasError;

    return Theme(
      data: themedData,
      child: Scaffold(
        backgroundColor: colors.surfacePrimary,
        appBar: AppBar(
          backgroundColor: colors.surfacePrimary,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: colors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                path,
                style: InterceptlyTheme.typography.bodyMediumBold.copyWith(
                  fontSize: 14,
                  color: colors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (host.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  host,
                  style: InterceptlyTheme.typography.bodySmallRegular.copyWith(
                    fontSize: 11,
                    color: colors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: _buildStatusBadge(
                entry: entry,
                isPending: isPending,
                colors: colors,
              ),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: InterceptlyTheme.indigo500,
            labelColor: InterceptlyTheme.indigo400,
            unselectedLabelColor: colors.textTertiary,
            dividerColor: InterceptlyGlobalColor.transparent,
            tabs: const [
              Tab(text: 'Messages'),
              Tab(text: 'Overview'),
            ],
          ),
        ),
        body: FutureBuilder<RequestRecord>(
          future: _recordFuture,
          initialData: _cachedRecord,
          builder: (context, snapshot) {
            final record = snapshot.data ?? _cachedRecord;
            return TabBarView(
              controller: _tabController,
              children: [
                RealtimeMessagesTab(
                  session: widget.session,
                  sessionId: entry.id,
                ),
                if (record != null)
                  _buildOverviewTab(record, isPending, colors)
                else
                  const Center(
                    child: CircularProgressIndicator(
                      color: InterceptlyTheme.indigo500,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusBadge({
    required RequestSummary entry,
    required bool isPending,
    required InterceptlyColors colors,
  }) {
    final String label;
    final Color fg;
    final Color bg;
    final Color border;

    if (isPending) {
      label = 'CONNECTED';
      fg = InterceptlyTheme.green400;
      bg = InterceptlyTheme.green500.withValues(alpha: 0.16);
      border = InterceptlyTheme.green500.withValues(alpha: 0.45);
    } else if (entry.hasError ||
        (entry.statusCode > 1000 && entry.statusCode != 1005)) {
      label = 'DROPPED';
      fg = InterceptlyTheme.red400;
      bg = InterceptlyTheme.red500.withValues(alpha: 0.16);
      border = InterceptlyTheme.red500.withValues(alpha: 0.45);
    } else {
      label = 'CLOSED';
      fg = colors.textSecondary;
      bg = colors.surfaceTertiary;
      border = InterceptlyTheme.dividerSubtle;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPending) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: fg,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: InterceptlyTheme.typography.monospace(
              InterceptlyTheme.typography.labelSmallBold.copyWith(
                fontSize: 10,
                color: fg,
                letterSpacing: 0.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(
    RequestRecord record,
    bool isPending,
    InterceptlyColors colors,
  ) {
    final decodeEnabled = widget.session.preferences.urlDecodeEnabled;
    String displayUrl = record.url;
    if (decodeEnabled) {
      try {
        displayUrl = Uri.decodeFull(record.url);
      } catch (_) {}
    }

    final String statusValue;
    if (isPending) {
      statusValue = 'CONNECTED (Open)';
    } else if (record.hasError ||
        (record.statusCode > 1000 && record.statusCode != 1005)) {
      statusValue = 'DROPPED (${record.statusCode})';
    } else {
      statusValue = 'CLOSED (${record.statusCode})';
    }

    final currentNow = (widget.nowProvider ?? DateTime.now)();
    final String durationValue;
    if (isPending) {
      final elapsed = currentNow.difference(record.timestamp);
      durationValue = formatDuration(elapsed);
    } else {
      durationValue = formatDuration(Duration(milliseconds: record.durationMs));
    }

    final frameCounts = widget.session.getRealtimeFrameCounts(record.id);

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildRow('URL', displayUrl, colors),
        const SizedBox(height: 16),
        _buildRow('Method / Protocol', record.method, colors),
        const SizedBox(height: 16),
        _buildRow('Status', statusValue, colors),
        const SizedBox(height: 16),
        _buildRow('Duration', durationValue, colors),
        const SizedBox(height: 16),
        _buildRow(
          'Frames',
          '↓ ${frameCounts.incoming} received, ↑ ${frameCounts.outgoing} sent (${frameCounts.total} total)',
          colors,
        ),
        if (record.hasError && record.errorMessage != null) ...[
          const SizedBox(height: 16),
          _buildRow(
            'Error',
            record.errorMessage!,
            colors,
            valueColor: InterceptlyTheme.yellow400,
          ),
        ],
        const SizedBox(height: 16),
        _buildRow('Time', record.timestamp.toIso8601String(), colors),
        if (record.requestHeaders.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Handshake Request Headers',
            style: InterceptlyTheme.typography.bodyMediumBold.copyWith(
              color: colors.textPrimary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(InterceptlyTheme.radius.md),
              border: Border.all(color: InterceptlyTheme.dividerSubtle),
            ),
            child: Column(
              children: [
                for (final entry in record.requestHeaders.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            entry.key,
                            style: InterceptlyTheme.typography.monospace(
                              InterceptlyTheme.typography.bodySmallBold
                                  .copyWith(color: colors.textSecondary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: Text(
                            entry.value,
                            style: InterceptlyTheme.typography.monospace(
                              InterceptlyTheme.typography.bodySmallRegular
                                  .copyWith(color: colors.textPrimary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRow(
    String label,
    String value,
    InterceptlyColors colors, {
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: InterceptlyTheme.typography.bodySmallRegular.copyWith(
            color: colors.textTertiary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: InterceptlyTheme.typography.monospace(
            InterceptlyTheme.typography.bodyMediumRegular.copyWith(
              color: valueColor ?? colors.textPrimary,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
