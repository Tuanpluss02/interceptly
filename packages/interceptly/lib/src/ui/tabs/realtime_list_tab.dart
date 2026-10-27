import 'dart:async';

import 'package:flutter/material.dart';

import '../../model/request_summary.dart';
import '../detail/realtime_detail_page.dart';
import '../format.dart';
import '../scope/interceptly_scope.dart';
import 'realtime_log_item.dart';

/// Minimal list of realtime connections without search, filter or grouping.
class RealtimeListTab extends StatefulWidget {
  /// Creates a realtime-only list.
  const RealtimeListTab({
    super.key,
    this.nowProvider,
  });

  /// Clock used for live duration of active connections.
  final DateTime Function()? nowProvider;

  @override
  State<RealtimeListTab> createState() => _RealtimeListTabState();
}

class _RealtimeListTabState extends State<RealtimeListTab> {
  final Map<String, String> _displayUrlCache = {};
  bool? _cachedUrlDecodeSetting;
  InterceptlyScopeController? _scope;
  bool _hasActiveConnections = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = InterceptlyScope.read(context);
    if (!identical(next, _scope)) {
      _scope?.removeListener(_onScopeUpdated);
      _scope = next;
      _scope!.addListener(_onScopeUpdated);
      _refreshActiveFlag();
    }
  }

  @override
  void dispose() {
    _scope?.removeListener(_onScopeUpdated);
    _scope = null;
    _displayUrlCache.clear();
    super.dispose();
  }

  /// Refreshes the cached active-connection flag without a global ticker.
  ///
  /// Per-row duration widgets own their 1s timers, so the list itself only
  /// rebuilds on scope notifications.
  void _onScopeUpdated() {
    final scope = _scope;
    if (scope == null || !mounted) return;
    final hasActive = scope.entries.any(
      (e) => e.isRealtime && e.statusCode == 0 && !e.hasError,
    );
    if (hasActive != _hasActiveConnections) {
      _hasActiveConnections = hasActive;
    }
    if (mounted) setState(() {});
  }

  /// Recomputes the active-connection flag for the current scope.
  void _refreshActiveFlag() {
    final scope = _scope;
    if (scope == null) return;
    _hasActiveConnections = scope.entries.any(
      (e) => e.isRealtime && e.statusCode == 0 && !e.hasError,
    );
  }

  /// Returns the display URL honoring the url-decode preference.
  String _getDisplayUrl(RequestSummary entry, bool decodeEnabled) {
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

  @override
  Widget build(BuildContext context) {
    final scope = InterceptlyScope.of(context);

    final entries = scope.entries.where((e) => e.isRealtime).toList();

    if (entries.isEmpty) {
      return const Center(
        child: Text('No WebSocket connections yet.'),
      );
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom + 88;

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(12, 10, 12, bottomInset),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return KeyedSubtree(
          key: ValueKey(entry.id),
          child: _RealtimeRow(
            entry: entry,
            scope: scope,
            nowProvider: widget.nowProvider,
            displayUrl:
                _getDisplayUrl(entry, scope.preferences.urlDecodeEnabled),
          ),
        );
      },
    );
  }
}

/// Single realtime row owning its 1s duration timer.
///
/// Isolating the ticker per row prevents the entire list from rebuilding
/// every second while a connection stays open.
class _RealtimeRow extends StatefulWidget {
  const _RealtimeRow({
    required this.entry,
    required this.scope,
    required this.displayUrl,
    this.nowProvider,
  });

  final RequestSummary entry;
  final InterceptlyScopeController scope;
  final String displayUrl;
  final DateTime Function()? nowProvider;

  @override
  State<_RealtimeRow> createState() => _RealtimeRowState();
}

class _RealtimeRowState extends State<_RealtimeRow> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (_isPending) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(covariant _RealtimeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isPending && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!_isPending && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  bool get _isPending => widget.entry.statusCode == 0 && !widget.entry.hasError;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final isPending = _isPending;
    final String durationText;
    if (isPending) {
      final currentNow = (widget.nowProvider ?? DateTime.now)();
      durationText = formatDuration(currentNow.difference(entry.timestamp));
    } else {
      durationText = formatDuration(Duration(milliseconds: entry.durationMs));
    }

    final time =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}';

    return RealtimeLogItem(
      method: entry.method,
      url: widget.displayUrl,
      time: time,
      duration: durationText,
      status: entry.statusCode,
      hasError: entry.hasError,
      isPending: isPending,
      frameCounts: widget.scope.getRealtimeFrameCounts(entry.id),
      frameCountsNotifier:
          widget.scope.getRealtimeFrameCountsNotifier(entry.id),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InterceptlyScope(
            controller: widget.scope,
            child: RealtimeDetailPage(
              entry: entry,
              nowProvider: widget.nowProvider,
            ),
          ),
        ),
      ),
    );
  }
}
