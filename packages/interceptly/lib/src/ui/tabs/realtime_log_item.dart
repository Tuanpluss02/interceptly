import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

import '../../model/realtime_frame.dart';
import 'log_row_shell.dart';

/// Log row for a realtime connection with live frame counts.
class RealtimeLogItem extends StatelessWidget {
  const RealtimeLogItem({
    super.key,
    required this.method,
    required this.url,
    required this.time,
    required this.duration,
    required this.status,
    required this.hasError,
    required this.isPending,
    required this.onTap,
    this.frameCounts,
    this.frameCountsNotifier,
  });

  final String method;
  final String url;
  final String time;
  final String duration;
  final int status;
  final bool hasError;
  final bool isPending;
  final RealtimeFrameCounts? frameCounts;
  final ValueListenable<RealtimeFrameCounts>? frameCountsNotifier;
  final VoidCallback onTap;

  /// Metadata line with frame counts for a snapshot of [counts].
  String buildMetaLine(RealtimeFrameCounts counts) {
    return '$time · $duration · ↓ ${counts.incoming}  ↑ ${counts.outgoing}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = InterceptlyTheme.colorsOf(context);
    final statusLook = LogStatusLook.realtime(
      status: status,
      isPending: isPending,
      palette: colors,
      hasError: hasError,
    );

    final String statusLabel;
    if (isPending) {
      statusLabel = 'CONNECTED';
    } else if (hasError || (status > 1000 && status != 1005)) {
      statusLabel = 'DROPPED';
    } else {
      statusLabel = 'CLOSED';
    }

    final statusBadge = isPending
        ? LogStatusBadge.liveDot(look: statusLook, label: statusLabel)
        : LogStatusBadge.realtime(look: statusLook, label: statusLabel);

    final Widget meta;
    if (frameCountsNotifier != null) {
      meta = ValueListenableBuilder<RealtimeFrameCounts>(
        valueListenable: frameCountsNotifier!,
        builder: (context, counts, _) {
          return LogMetaText(buildMetaLine(counts));
        },
      );
    } else {
      meta = LogMetaText(
          buildMetaLine(frameCounts ?? const RealtimeFrameCounts()));
    }

    return LogRowShell(
      method: method,
      url: url,
      statusBadge: statusBadge,
      meta: meta,
      onTap: onTap,
      semanticsLabel: '$method $url, status $statusLabel',
    );
  }
}
