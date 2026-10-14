import 'package:flutter/material.dart';
import 'package:interceptly/src/model/realtime_frame.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';

import 'realtime_formatters.dart';

/// Renders the expanded or collapsed payload of a [RealtimeFrame].
class RealtimePayloadView extends StatelessWidget {
  final RealtimeFrame frame;
  final bool isInspected;
  final dynamic parsedJson;
  final VoidCallback onToggleInspect;

  const RealtimePayloadView({
    super.key,
    required this.frame,
    required this.isInspected,
    required this.parsedJson,
    required this.onToggleInspect,
  });

  @override
  Widget build(BuildContext context) {
    if (isInspected) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                parsedJson != null ? 'JSON PAYLOAD' : 'RAW PAYLOAD',
                style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
                  color: InterceptlyTheme.textMuted,
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
              ),
              GestureDetector(
                key: ValueKey('frame_collapse_${frame.id}'),
                onTap: onToggleInspect,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Collapse',
                      style:
                          InterceptlyTheme.typography.labelSmallMedium.copyWith(
                        color: InterceptlyTheme.indigo400,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.keyboard_arrow_up,
                      size: 14,
                      color: InterceptlyTheme.indigo400,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          parsedJson != null
              ? JsonViewer(data: parsedJson)
              : SelectableText(
                  getFramePayloadString(frame),
                  style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                    fontSize: 12,
                    color: InterceptlyTheme.textPrimary,
                  ),
                ),
        ],
      );
    }

    return InkWell(
      key: ValueKey('frame_payload_${frame.id}'),
      borderRadius: BorderRadius.vertical(
        bottom: Radius.circular(InterceptlyTheme.radius.md),
      ),
      onTap: onToggleInspect,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              getFramePayloadString(frame),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                fontSize: 12,
                color: InterceptlyTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(
            Icons.keyboard_arrow_down,
            size: 16,
            color: InterceptlyTheme.textMuted,
          ),
        ],
      ),
    );
  }
}
