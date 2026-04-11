import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

class RequestLogItem extends StatelessWidget {
  const RequestLogItem({
    super.key,
    required this.method,
    required this.url,
    required this.time,
    required this.duration,
    required this.status,
    required this.hasError,
    required this.isPending,
    required this.onTap,
    required this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
  });

  final String method;
  final String url;
  final String time;
  final String duration;
  final int status;
  final bool hasError;
  final bool isPending;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static ({String path, String host}) _splitUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasAuthority) {
      final path = uri.path.isEmpty ? '/' : uri.path;
      return (path: path, host: uri.host);
    }
    return (path: url, host: '');
  }

  @override
  Widget build(BuildContext context) {
    final colors = InterceptlyTheme.colors;
    final mStyle = InterceptlyTheme.getMethodStyle(method);
    final isErrorWithoutStatus = status == 0 && hasError;
    final sStyle = isErrorWithoutStatus
        ? const StatusStyle(
            bg: InterceptlyTheme.red500,
            text: InterceptlyGlobalColor.white,
          )
        : InterceptlyTheme.getStatusStyle(status);

    final (:path, :host) = _splitUrl(url);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      hoverColor: InterceptlyTheme.hoverOverlay,
      child: Container(
        color: isSelected ? colors.actionPrimary.withValues(alpha: 0.08) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            // ── Checkbox (selection mode only) ──────────────────────────────
            if (isSelectionMode) ...[
              _SelectionCheckbox(
                isSelected: isSelected,
                actionColor: colors.actionPrimary,
                onTap: onTap,
              ),
              const SizedBox(width: 10),
            ],

            // ── Method badge ─────────────────────────────────────────────────
            Container(
              width: 48,
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              decoration: BoxDecoration(
                color: mStyle.bg.withValues(alpha: 0.22),
                border: Border.all(color: mStyle.border.withValues(alpha: 0.8)),
                borderRadius: BorderRadius.circular(
                  InterceptlyTheme.radius.sm + 2,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                method,
                style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
                  color: mStyle.text,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
            ),

            const SizedBox(width: 12),

            // ── Path / host / meta ──────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    path,
                    style: InterceptlyTheme.typography.bodyMediumMedium
                        .copyWith(fontSize: 13, color: colors.textPrimary),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (host.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      host,
                      style: InterceptlyTheme.typography.bodyMediumRegular
                          .copyWith(fontSize: 12, color: colors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    '$time • $duration',
                    style:
                        InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                      fontSize: 11,
                      color: InterceptlyTheme.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // ── Status badge ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 4.0,
              ),
              decoration: BoxDecoration(
                color: sStyle.bg,
                borderRadius: BorderRadius.circular(12.0),
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
                      isErrorWithoutStatus ? 'ERR' : status.toString(),
                      style: InterceptlyTheme.typography.bodyMediumBold
                          .copyWith(fontSize: 11, color: sStyle.text),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionCheckbox extends StatelessWidget {
  const _SelectionCheckbox({
    required this.isSelected,
    required this.actionColor,
    required this.onTap,
  });

  final bool isSelected;
  final Color actionColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: isSelected ? actionColor : InterceptlyGlobalColor.transparent,
          borderRadius: BorderRadius.circular(InterceptlyTheme.radius.sm),
          border: Border.all(
            color: isSelected ? actionColor : InterceptlyTheme.controlMuted,
            width: 1.5,
          ),
        ),
        child: isSelected
            ? Icon(Icons.check, size: 14, color: InterceptlyGlobalColor.white)
            : null,
      ),
    );
  }
}
