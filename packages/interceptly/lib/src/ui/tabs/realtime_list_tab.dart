import 'dart:async';

import 'package:flutter/material.dart';

import '../../model/request_summary.dart';
import '../../session/inspector_session_view.dart';
import '../detail/realtime_detail_page.dart';
import '../format.dart';
import 'realtime_log_item.dart';

/// Minimal list of realtime connections without search, filter or grouping.
class RealtimeListTab extends StatefulWidget {
  /// Creates a realtime-only list bound to [session].
  const RealtimeListTab({
    super.key,
    required this.session,
    @visibleForTesting this.nowProvider,
  });

  /// Session providing realtime entries and live frame counts.
  final InspectorSessionView session;

  /// Clock used for live duration of active connections.
  final DateTime Function()? nowProvider;

  @override
  State<RealtimeListTab> createState() => _RealtimeListTabState();
}

class _RealtimeListTabState extends State<RealtimeListTab> {
  Timer? _liveTicker;
  final Map<String, String> _displayUrlCache = {};
  bool? _cachedUrlDecodeSetting;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionUpdated);
    _updateLiveTicker();
  }

  @override
  void didUpdateWidget(covariant RealtimeListTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session != oldWidget.session) {
      oldWidget.session.removeListener(_onSessionUpdated);
      widget.session.addListener(_onSessionUpdated);
      _updateLiveTicker();
    }
  }

  @override
  void dispose() {
    _liveTicker?.cancel();
    _liveTicker = null;
    widget.session.removeListener(_onSessionUpdated);
    _displayUrlCache.clear();
    super.dispose();
  }

  /// Restarts or stops the 1s ticker based on active connections.
  void _onSessionUpdated() {
    _updateLiveTicker();
  }

  /// Starts a 1s rebuild loop while any connection is still open.
  void _updateLiveTicker() {
    final hasActive = widget.session.entries.any(
      (e) => e.isRealtime && e.statusCode == 0 && !e.hasError,
    );
    if (hasActive) {
      _liveTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _liveTicker?.cancel();
      _liveTicker = null;
    }
  }

  /// Returns the display URL honoring the url-decode preference.
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final entries =
            widget.session.entries.where((e) => e.isRealtime).toList();

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
              child: _buildRealtimeItem(context, entry),
            );
          },
        );
      },
    );
  }

  /// Builds one realtime row with live duration and frame counts.
  Widget _buildRealtimeItem(BuildContext context, RequestSummary entry) {
    final isPending = entry.statusCode == 0 && !entry.hasError;
    final String durationText;
    if (isPending) {
      final currentNow = (widget.nowProvider ?? DateTime.now)();
      durationText = formatDuration(currentNow.difference(entry.timestamp));
    } else {
      durationText =
          formatDuration(Duration(milliseconds: entry.durationMs));
    }

    final time =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}';

    return RealtimeLogItem(
      method: entry.method,
      url: _getDisplayUrl(entry),
      time: time,
      duration: durationText,
      status: entry.statusCode,
      hasError: entry.hasError,
      isPending: isPending,
      frameCounts: widget.session.getRealtimeFrameCounts(entry.id),
      frameCountsNotifier:
          widget.session.getRealtimeFrameCountsNotifier(entry.id),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RealtimeDetailPage(
            entry: entry,
            session: widget.session,
            nowProvider: widget.nowProvider,
          ),
        ),
      ),
    );
  }
}
