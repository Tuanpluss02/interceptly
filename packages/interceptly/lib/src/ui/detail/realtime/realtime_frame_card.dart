import 'package:flutter/material.dart';
import 'package:interceptly/src/model/realtime_frame.dart';
import 'package:interceptly/src/ui/format.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

import 'realtime_formatters.dart';
import 'realtime_payload_view.dart';

/// Card item representing a single captured [RealtimeFrame] in the message list.
class RealtimeFrameCard extends StatelessWidget {
  final RealtimeFrame frame;
  final bool isInspected;
  final dynamic parsedJson;
  final VoidCallback onToggleInspect;
  final VoidCallback onCopy;
  final VoidCallback? onResend;
  final VoidCallback? onEdit;

  const RealtimeFrameCard({
    super.key,
    required this.frame,
    required this.isInspected,
    required this.parsedJson,
    required this.onToggleInspect,
    required this.onCopy,
    this.onResend,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isIncoming = frame.direction == FrameDirection.incoming;
    final dirColor =
        isIncoming ? InterceptlyTheme.green400 : InterceptlyTheme.blue400;
    final dirBgColor = isIncoming
        ? InterceptlyTheme.green500.withValues(alpha: 0.10)
        : InterceptlyTheme.blue500.withValues(alpha: 0.10);
    final dirLabel = isIncoming ? '↓ IN' : '↑ OUT';

    final directionBadge = Container(
      key: ValueKey('frame_direction_${frame.id}'),
      padding: const EdgeInsets.symmetric(
        horizontal: 6.0,
        vertical: 2.0,
      ),
      decoration: BoxDecoration(
        color: dirColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4.0),
        border: Border.all(
          color: dirColor.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        dirLabel,
        style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
          color: dirColor,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    final typeBadge = Container(
      key: ValueKey('frame_type_${frame.id}'),
      padding: const EdgeInsets.symmetric(
        horizontal: 6.0,
        vertical: 2.0,
      ),
      decoration: BoxDecoration(
        color: InterceptlyTheme.controlMuted,
        borderRadius: BorderRadius.circular(4.0),
        border: Border.all(color: InterceptlyTheme.dividerSubtle),
      ),
      child: Text(
        frameTypeLabel(frame.type),
        style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
          color: frame.isBinary
              ? InterceptlyTheme.yellow400
              : frame.isText
                  ? InterceptlyTheme.indigo400
                  : InterceptlyTheme.textMuted,
          fontSize: 10.5,
        ),
      ),
    );

    final eventBadge = frame.eventName != null
        ? Container(
            key: ValueKey('frame_event_${frame.id}'),
            padding: const EdgeInsets.symmetric(
              horizontal: 6.0,
              vertical: 2.0,
            ),
            decoration: BoxDecoration(
              color: InterceptlyTheme.indigo500.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4.0),
              border: Border.all(
                color: InterceptlyTheme.indigo500.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              frame.eventName!,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
                color: InterceptlyTheme.indigo400,
                fontSize: 10.5,
              ),
            ),
          )
        : null;

    final sizeText = Text(
      formatBytes(frame.payloadSizeBytes),
      key: ValueKey('frame_size_${frame.id}'),
      style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
        color: InterceptlyTheme.textMuted,
        fontSize: 10.5,
      ),
    );

    final timeText = Text(
      formatFrameTimestamp(frame.timestamp),
      key: ValueKey('frame_time_${frame.id}'),
      style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
        color: InterceptlyTheme.textMuted,
        fontSize: 10.5,
      ),
    );

    final buttonStyle = IconButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(24, 24),
      padding: EdgeInsets.zero,
    );

    final actionButtons = <Widget>[
      IconButton(
        key: ValueKey('frame_inspect_${frame.id}'),
        tooltip: isInspected ? 'Collapse payload' : 'Inspect payload',
        padding: EdgeInsets.zero,
        style: buttonStyle,
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        icon: Icon(
          isInspected ? Icons.unfold_less : Icons.unfold_more,
          size: 14,
          color: isInspected
              ? InterceptlyTheme.indigo400
              : InterceptlyTheme.textMuted,
        ),
        onPressed: onToggleInspect,
      ),
      const SizedBox(width: 2),
      IconButton(
        key: ValueKey('frame_copy_${frame.id}'),
        tooltip: 'Copy payload',
        padding: EdgeInsets.zero,
        style: buttonStyle,
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        icon: const Icon(
          Icons.copy,
          size: 13,
          color: InterceptlyTheme.textMuted,
        ),
        onPressed: onCopy,
      ),
      if (onEdit != null) ...[
        const SizedBox(width: 2),
        IconButton(
          key: ValueKey('frame_edit_${frame.id}'),
          tooltip: 'Edit message',
          padding: EdgeInsets.zero,
          style: buttonStyle,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          icon: const Icon(
            Icons.edit_note_rounded,
            size: 16,
            color: InterceptlyTheme.textMuted,
          ),
          onPressed: onEdit,
        ),
      ],
      if (onResend != null) ...[
        const SizedBox(width: 2),
        IconButton(
          key: ValueKey('frame_resend_${frame.id}'),
          tooltip: 'Resend message',
          padding: EdgeInsets.zero,
          style: buttonStyle,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          icon: const Icon(
            Icons.replay_rounded,
            size: 15,
            color: InterceptlyTheme.textMuted,
          ),
          onPressed: onResend,
        ),
      ],
    ];

    return Container(
      key: ValueKey('frame_card_${frame.id}'),
      margin: const EdgeInsets.only(bottom: 10.0),
      decoration: BoxDecoration(
        color: InterceptlyTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(InterceptlyTheme.radius.md),
        border: Border.all(color: InterceptlyTheme.dividerSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            decoration: BoxDecoration(
              color: dirBgColor,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(InterceptlyTheme.radius.md),
              ),
              border: Border(
                bottom: BorderSide(color: InterceptlyTheme.dividerSubtle),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 480;
                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                directionBadge,
                                const SizedBox(width: 6),
                                typeBadge,
                                if (eventBadge != null) ...[
                                  const SizedBox(width: 6),
                                  Expanded(child: eventBadge),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          ...actionButtons,
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          sizeText,
                          const Spacer(),
                          timeText,
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          directionBadge,
                          const SizedBox(width: 8),
                          typeBadge,
                          if (eventBadge != null) ...[
                            const SizedBox(width: 8),
                            Expanded(child: eventBadge),
                          ],
                          const SizedBox(width: 8),
                          sizeText,
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    timeText,
                    const SizedBox(width: 4),
                    ...actionButtons,
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: RealtimePayloadView(
              frame: frame,
              isInspected: isInspected,
              parsedJson: parsedJson,
              onToggleInspect: onToggleInspect,
            ),
          ),
        ],
      ),
    );
  }
}
