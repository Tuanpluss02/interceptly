import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

import '../../model/search_match_scope.dart';
import '../format.dart';
import 'log_row_shell.dart';

/// Log row for a single REST request/response exchange.
class RestLogItem extends StatelessWidget {
  const RestLogItem({
    super.key,
    required this.method,
    required this.url,
    required this.time,
    required this.duration,
    required this.status,
    required this.hasError,
    required this.isPending,
    required this.responseSizeBytes,
    required this.onTap,
    required this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.searchScopes,
    this.highlightQuery,
  });

  final String method;
  final String url;
  final String time;
  final String duration;
  final int status;
  final bool hasError;
  final bool isPending;
  final int responseSizeBytes;
  final bool isSelectionMode;
  final bool isSelected;
  final Set<SearchMatchScope>? searchScopes;
  final String? highlightQuery;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Metadata line with response size for completed rows.
  String buildMetaLine() {
    final hasSize = !isPending && !(status == 0 && hasError);
    if (hasSize) {
      return '$time · $duration · ${formatBytes(responseSizeBytes)}';
    }
    return '$time · $duration';
  }

  @override
  Widget build(BuildContext context) {
    final colors = InterceptlyTheme.colorsOf(context);
    final isErrorWithoutStatus = status == 0 && hasError;
    final statusLook = LogStatusLook.rest(
      status: status,
      isPending: isPending,
      isErrorWithoutStatus: isErrorWithoutStatus,
      palette: colors,
    );

    final String statusLabel;
    if (isErrorWithoutStatus) {
      statusLabel = 'ERR';
    } else {
      statusLabel = '$status';
    }

    final statusBadge = isPending
        ? LogStatusBadge.spinner(look: statusLook)
        : LogStatusBadge.rest(look: statusLook, label: statusLabel);

    final hasScopes = searchScopes != null && searchScopes!.isNotEmpty;

    return LogRowShell(
      method: method,
      url: url,
      statusBadge: statusBadge,
      meta: LogMetaText(buildMetaLine()),
      onTap: onTap,
      onLongPress: onLongPress,
      highlightQuery: highlightQuery,
      scopeBadges:
          hasScopes ? LogScopeBadges(scopes: searchScopes!) : null,
      isSelectionMode: isSelectionMode,
      isSelected: isSelected,
      semanticsLabel: '$method $url, status $statusLabel',
    );
  }
}
