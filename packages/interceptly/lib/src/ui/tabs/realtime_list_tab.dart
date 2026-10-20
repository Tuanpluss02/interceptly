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
  Timer? _liveTicker;
  final Map<String, String> _displayUrlCache = {};
  bool? _cachedUrlDecodeSetting;

  @override
  void dispose() {
    _liveTicker?.cancel();
    _liveTicker = null;
    _displayUrlCache.clear();
    super.dispose();
  }

  /// Starts a 1s rebuild loop while any connection is still open.
  void _updateLiveTicker(InterceptlyScopeController scope) {
    final hasActive = scope.entries.any(
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
    _updateLiveTicker(scope);

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
          child: _buildRealtimeItem(context, scope, entry),
        );
      },
    );
  }

  /// Builds one realtime row with live duration and frame counts.
  Widget _buildRealtimeItem(
    BuildContext context,
    InterceptlyScopeController scope,
    RequestSummary entry,
  ) {
    final isPending = entry.statusCode == 0 && !entry.hasError;
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
      url: _getDisplayUrl(entry, scope.preferences.urlDecodeEnabled),
      time: time,
      duration: durationText,
      status: entry.statusCode,
      hasError: entry.hasError,
      isPending: isPending,
      frameCounts: scope.getRealtimeFrameCounts(entry.id),
      frameCountsNotifier: scope.getRealtimeFrameCountsNotifier(entry.id),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InterceptlyScope(
            controller: scope,
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
