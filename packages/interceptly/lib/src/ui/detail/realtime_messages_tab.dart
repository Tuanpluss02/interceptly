import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:interceptly/src/model/realtime_frame.dart';
import 'package:interceptly/src/session/inspector_session_view.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';
import 'package:interceptly/src/ui/widgets/toast_notification.dart';

import 'detail_search.dart';

/// Tab widget for displaying live captured WebSocket and realtime frames.
class RealtimeMessagesTab extends StatefulWidget {
  /// Unique identifier of the connection / session whose frames are displayed.
  final String sessionId;

  /// Active inspector session providing captured realtime frames.
  final InspectorSessionView? session;

  /// Creates a [RealtimeMessagesTab] for the specified [sessionId].
  const RealtimeMessagesTab({
    super.key,
    required this.sessionId,
    this.session,
  });

  @override
  State<RealtimeMessagesTab> createState() => _RealtimeMessagesTabState();
}

class _RealtimeMessagesTabState extends State<RealtimeMessagesTab> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _inspectedFrameIds = <String>{};

  String _searchQuery = '';
  FrameDirection? _directionFilter;
  FrameType? _typeFilter;

  @override
  void initState() {
    super.initState();
    widget.session?.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(covariant RealtimeMessagesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session != oldWidget.session) {
      oldWidget.session?.removeListener(_onSessionChanged);
      widget.session?.addListener(_onSessionChanged);
    }
  }

  @override
  void dispose() {
    widget.session?.removeListener(_onSessionChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleInspect(String frameId) {
    setState(() {
      if (_inspectedFrameIds.contains(frameId)) {
        _inspectedFrameIds.remove(frameId);
      } else {
        _inspectedFrameIds.add(frameId);
      }
    });
  }

  String _formatTimestamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  String _frameTypeLabel(FrameType type) {
    switch (type) {
      case FrameType.text:
        return 'Text';
      case FrameType.binary:
        return 'Binary';
      case FrameType.ping:
        return 'Ping';
      case FrameType.pong:
        return 'Pong';
      case FrameType.close:
        return 'Close';
      case FrameType.ack:
        return 'Ack';
    }
  }

  String _getPayloadString(RealtimeFrame frame) {
    if (frame.textPayload != null) {
      return frame.textPayload!;
    }
    if (frame.binaryPayload != null) {
      return _formatBinaryPreview(frame.binaryPayload!);
    }
    return frame.type.name.toUpperCase();
  }

  String _formatBinaryPreview(Uint8List bytes) {
    if (bytes.isEmpty) return '[empty binary]';
    final sample = bytes.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    final suffix = bytes.length > 16 ? '...' : '';
    return '[binary: ${bytes.length} bytes] $sample$suffix';
  }

  dynamic _tryParseJson(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  void _copyPayload(RealtimeFrame frame) {
    final text = _getPayloadString(frame);
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      if (mounted) {
        ToastNotification.show('Payload copied to clipboard', contextHint: context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final allFrames =
        widget.session?.getRealtimeFrames(widget.sessionId) ?? const <RealtimeFrame>[];

    if (allFrames.isEmpty) {
      return Center(
        child: Text(
          'No WebSocket messages captured.',
          style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
            color: InterceptlyTheme.textMuted,
          ),
        ),
      );
    }

    final query = _searchQuery.trim().toLowerCase();
    final filteredFrames = allFrames.where((frame) {
      if (_directionFilter != null && frame.direction != _directionFilter) {
        return false;
      }
      if (_typeFilter != null && frame.type != _typeFilter) {
        return false;
      }
      if (query.isNotEmpty) {
        final payloadText = _getPayloadString(frame).toLowerCase();
        final typeText = frame.type.name.toLowerCase();
        if (!payloadText.contains(query) && !typeText.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();

    return Column(
      children: [
        _buildFilterHeader(),
        Expanded(
          child: filteredFrames.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 36,
                        color: InterceptlyTheme.textMuted,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No matching messages.',
                        style: InterceptlyTheme.typography.bodyMediumMedium.copyWith(
                          color: InterceptlyTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  itemCount: filteredFrames.length,
                  itemBuilder: (context, index) {
                    final frame = filteredFrames[index];
                    return _buildFrameCard(frame);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterHeader() {
    final isAllSelected = _directionFilter == null && _typeFilter == null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16.0, 10.0, 16.0, 10.0),
      decoration: BoxDecoration(
        color: InterceptlyTheme.surface,
        border: Border(
          bottom: BorderSide(color: InterceptlyTheme.dividerSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
              color: InterceptlyTheme.textPrimary,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'Search messages...',
              hintStyle: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                color: InterceptlyTheme.textMuted,
                fontSize: 13,
              ),
              prefixIcon: const Icon(
                Icons.search,
                size: 16,
                color: InterceptlyTheme.textMuted,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.clear,
                        size: 16,
                        color: InterceptlyTheme.textMuted,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 8.0,
              ),
              filled: true,
              fillColor: InterceptlyTheme.surfaceContainer,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(InterceptlyTheme.radius.md),
                borderSide: BorderSide(color: InterceptlyTheme.dividerSubtle),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(InterceptlyTheme.radius.md),
                borderSide: BorderSide(color: InterceptlyTheme.dividerSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(InterceptlyTheme.radius.md),
                borderSide: const BorderSide(color: InterceptlyTheme.indigo500),
              ),
            ),
            onChanged: (val) {
              setState(() {
                _searchQuery = val;
              });
            },
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  key: const ValueKey('chip_all'),
                  label: 'All',
                  isSelected: isAllSelected,
                  onTap: () {
                    setState(() {
                      _directionFilter = null;
                      _typeFilter = null;
                    });
                  },
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  key: const ValueKey('chip_incoming'),
                  label: '↓ IN',
                  isSelected: _directionFilter == FrameDirection.incoming,
                  activeColor: InterceptlyTheme.green400,
                  activeBgColor: InterceptlyTheme.green500.withValues(alpha: 0.15),
                  onTap: () {
                    setState(() {
                      _directionFilter = _directionFilter == FrameDirection.incoming
                          ? null
                          : FrameDirection.incoming;
                    });
                  },
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  key: const ValueKey('chip_outgoing'),
                  label: '↑ OUT',
                  isSelected: _directionFilter == FrameDirection.outgoing,
                  activeColor: InterceptlyTheme.blue400,
                  activeBgColor: InterceptlyTheme.blue500.withValues(alpha: 0.15),
                  onTap: () {
                    setState(() {
                      _directionFilter = _directionFilter == FrameDirection.outgoing
                          ? null
                          : FrameDirection.outgoing;
                    });
                  },
                ),
                const SizedBox(width: 8),
                Container(
                  height: 16,
                  width: 1,
                  color: InterceptlyTheme.dividerSubtle,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  key: const ValueKey('chip_text'),
                  label: 'Text',
                  isSelected: _typeFilter == FrameType.text,
                  activeColor: InterceptlyTheme.indigo400,
                  activeBgColor: InterceptlyTheme.indigo500.withValues(alpha: 0.15),
                  onTap: () {
                    setState(() {
                      _typeFilter =
                          _typeFilter == FrameType.text ? null : FrameType.text;
                    });
                  },
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  key: const ValueKey('chip_binary'),
                  label: 'Binary',
                  isSelected: _typeFilter == FrameType.binary,
                  activeColor: InterceptlyTheme.yellow400,
                  activeBgColor: InterceptlyTheme.yellow500.withValues(alpha: 0.15),
                  onTap: () {
                    setState(() {
                      _typeFilter = _typeFilter == FrameType.binary
                          ? null
                          : FrameType.binary;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required Key key,
    required String label,
    required bool isSelected,
    Color? activeColor,
    Color? activeBgColor,
    required VoidCallback onTap,
  }) {
    final colors = InterceptlyTheme.colors;
    final fg = isSelected
        ? (activeColor ?? colors.actionPrimary)
        : colors.textSecondary;
    final bg = isSelected
        ? (activeBgColor ?? colors.actionPrimary.withValues(alpha: 0.12))
        : InterceptlyTheme.controlMuted;
    final border = isSelected
        ? (activeColor ?? colors.actionPrimary).withValues(alpha: 0.4)
        : InterceptlyTheme.dividerSubtle;

    return GestureDetector(
      key: key,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(InterceptlyTheme.radius.md),
          border: Border.all(color: border, width: 1.0),
        ),
        child: Text(
          label,
          style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
            color: fg,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildFrameCard(RealtimeFrame frame) {
    final isIncoming = frame.direction == FrameDirection.incoming;
    final dirColor =
        isIncoming ? InterceptlyTheme.green400 : InterceptlyTheme.blue400;
    final dirBgColor = isIncoming
        ? InterceptlyTheme.green500.withValues(alpha: 0.10)
        : InterceptlyTheme.blue500.withValues(alpha: 0.10);
    final dirLabel = isIncoming ? '↓ IN' : '↑ OUT';

    final isInspected = _inspectedFrameIds.contains(frame.id);
    final parsedJson = _tryParseJson(frame.textPayload);

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
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            decoration: BoxDecoration(
              color: dirBgColor,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(InterceptlyTheme.radius.md),
              ),
              border: Border(
                bottom: BorderSide(color: InterceptlyTheme.dividerSubtle),
              ),
            ),
            child: Row(
              children: [
                // Direction Badge
                Container(
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
                ),
                const SizedBox(width: 8),
                // Type Badge
                Container(
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
                    _frameTypeLabel(frame.type),
                    style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
                      color: frame.isBinary
                          ? InterceptlyTheme.yellow400
                          : frame.isText
                              ? InterceptlyTheme.indigo400
                              : InterceptlyTheme.textMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Payload Size Badge
                Text(
                  formatBytes(frame.payloadSizeBytes),
                  key: ValueKey('frame_size_${frame.id}'),
                  style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                    color: InterceptlyTheme.textMuted,
                    fontSize: 10.5,
                  ),
                ),
                const Spacer(),
                // Timestamp
                Text(
                  _formatTimestamp(frame.timestamp),
                  key: ValueKey('frame_time_${frame.id}'),
                  style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                    color: InterceptlyTheme.textMuted,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(width: 4),
                // Inspect / Expand Toggle Button
                IconButton(
                  key: ValueKey('frame_inspect_${frame.id}'),
                  tooltip: isInspected ? 'Collapse payload' : 'Inspect payload',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  icon: Icon(
                    isInspected ? Icons.unfold_less : Icons.unfold_more,
                    size: 14,
                    color: isInspected
                        ? InterceptlyTheme.indigo400
                        : InterceptlyTheme.textMuted,
                  ),
                  onPressed: () => _toggleInspect(frame.id),
                ),
                const SizedBox(width: 2),
                // Copy Button
                IconButton(
                  key: ValueKey('frame_copy_${frame.id}'),
                  tooltip: 'Copy payload',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  icon: const Icon(
                    Icons.copy,
                    size: 13,
                    color: InterceptlyTheme.textMuted,
                  ),
                  onPressed: () => _copyPayload(frame),
                ),
              ],
            ),
          ),
          // Payload Content
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: isInspected
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            parsedJson != null ? 'JSON PAYLOAD' : 'RAW PAYLOAD',
                            style: InterceptlyTheme.typography.labelSmallMedium
                                .copyWith(
                              color: InterceptlyTheme.textMuted,
                              fontSize: 10,
                              letterSpacing: 0.5,
                            ),
                          ),
                          GestureDetector(
                            key: ValueKey('frame_collapse_${frame.id}'),
                            onTap: () => _toggleInspect(frame.id),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Collapse',
                                  style: InterceptlyTheme
                                      .typography.labelSmallMedium
                                      .copyWith(
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
                              _getPayloadString(frame),
                              style: InterceptlyTheme
                                  .typography.bodyMediumRegular
                                  .copyWith(
                                fontSize: 12,
                                color: InterceptlyTheme.textPrimary,
                              ),
                            ),
                    ],
                  )
                : InkWell(
                    key: ValueKey('frame_payload_${frame.id}'),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(InterceptlyTheme.radius.md),
                    ),
                    onTap: () => _toggleInspect(frame.id),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _getPayloadString(frame),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: InterceptlyTheme
                                .typography.bodyMediumRegular
                                .copyWith(
                              fontSize: 12,
                              color: InterceptlyTheme.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.keyboard_arrow_down,
                          size: 16,
                          color: InterceptlyTheme.textMuted,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
