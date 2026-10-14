import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:interceptly/src/model/realtime_frame.dart';
import 'package:interceptly/src/model/realtime_protocol_type.dart';
import 'package:interceptly/src/session/inspector_session_view.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/widgets/toast_notification.dart';

import 'realtime/realtime_chat_bar.dart';
import 'realtime/realtime_filter_header.dart';
import 'realtime/realtime_formatters.dart';
import 'realtime/realtime_frame_card.dart';
import 'realtime/realtime_message_composer_sheet.dart';

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
  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _eventController = TextEditingController();
  final Set<String> _inspectedFrameIds = <String>{};
  final Map<String, dynamic> _parsedJsonCache = <String, dynamic>{};
  Timer? _searchDebounceTimer;

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
    _searchDebounceTimer?.cancel();
    _parsedJsonCache.clear();
    widget.session?.removeListener(_onSessionChanged);
    _searchController.dispose();
    _chatController.dispose();
    _eventController.dispose();
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

  void _copyPayload(RealtimeFrame frame) {
    final text = getFramePayloadString(frame);
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      if (mounted) {
        ToastNotification.show('Payload copied to clipboard',
            contextHint: context);
      }
    });
  }

  void _onEditFrame(RealtimeFrame frame) {
    final text = getFramePayloadString(frame);
    _chatController.text = text;
    if (frame.eventName != null) {
      _eventController.text = frame.eventName!;
    }
  }

  Future<void> _onResendFrame(RealtimeFrame frame) async {
    final canSend =
        widget.session?.canSendRealtimeMessage(widget.sessionId) ?? false;
    if (!canSend) {
      ToastNotification.show('Cannot send: connection is closed',
          contextHint: context);
      return;
    }

    final text = getFramePayloadString(frame);
    final draft = RealtimeMessageDraft(
      event: frame.eventName,
      payload: text,
    );

    try {
      await widget.session?.sendRealtimeMessage(widget.sessionId, draft);
    } catch (e) {
      if (mounted) {
        ToastNotification.show('Failed to resend message: $e',
            contextHint: context);
      }
    }
  }

  Future<void> _sendMessage() async {
    final payload = _chatController.text;
    if (payload.trim().isEmpty) return;
    final protocol = widget.session?.getRealtimeProtocol(widget.sessionId) ??
        RealtimeProtocolType.webSocket;
    final isSocketIo = protocol == RealtimeProtocolType.socketIo;
    final event = isSocketIo ? _eventController.text.trim() : null;

    final draft = RealtimeMessageDraft(
      event: event?.isEmpty ?? true ? null : event,
      payload: payload,
    );

    try {
      await widget.session?.sendRealtimeMessage(widget.sessionId, draft);
      _chatController.clear();
    } catch (e) {
      if (mounted) {
        ToastNotification.show('Failed to send message: $e',
            contextHint: context);
      }
    }
  }

  void _onExpandComposer() {
    final protocol = widget.session?.getRealtimeProtocol(widget.sessionId) ??
        RealtimeProtocolType.webSocket;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RealtimeMessageComposerSheet(
        protocolType: protocol,
        initialEvent: _eventController.text,
        initialPayload: _chatController.text,
        onSend: (draft) async {
          await widget.session?.sendRealtimeMessage(widget.sessionId, draft);
          _chatController.clear();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allFrames = widget.session?.getRealtimeFrames(widget.sessionId) ??
        const <RealtimeFrame>[];

    final Widget body;

    if (allFrames.isEmpty) {
      body = Expanded(
        child: Center(
          child: Text(
            'No WebSocket messages captured.',
            style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
              color: InterceptlyTheme.textMuted,
            ),
          ),
        ),
      );
    } else {
      final query = _searchQuery.trim().toLowerCase();
      final bool hasFilter =
          _directionFilter != null || _typeFilter != null || query.isNotEmpty;
      final List<RealtimeFrame> filteredFrames = hasFilter
          ? allFrames.where((frame) {
              if (_directionFilter != null &&
                  frame.direction != _directionFilter) {
                return false;
              }
              if (_typeFilter != null && frame.type != _typeFilter) {
                return false;
              }
              if (query.isNotEmpty) {
                final payloadText = getFramePayloadString(frame).toLowerCase();
                final typeText = frame.type.name.toLowerCase();
                if (!payloadText.contains(query) &&
                    !typeText.contains(query)) {
                  return false;
                }
              }
              return true;
            }).toList()
          : allFrames;

      body = Expanded(
        child: Column(
          children: [
            RealtimeFilterHeader(
              searchController: _searchController,
              searchQuery: _searchQuery,
              directionFilter: _directionFilter,
              typeFilter: _typeFilter,
              onSearchChanged: (val) {
                _searchDebounceTimer?.cancel();
                _searchDebounceTimer =
                    Timer(const Duration(milliseconds: 180), () {
                  if (mounted) {
                    setState(() {
                      _searchQuery = val;
                    });
                  }
                });
              },
              onSearchCleared: () {
                _searchDebounceTimer?.cancel();
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                });
              },
              onDirectionFilterChanged: (dir) =>
                  setState(() => _directionFilter = dir),
              onTypeFilterChanged: (t) => setState(() => _typeFilter = t),
            ),
            Expanded(
              child: filteredFrames.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.search_off,
                            size: 36,
                            color: InterceptlyTheme.textMuted,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No matching messages.',
                            style: InterceptlyTheme.typography.bodyMediumMedium
                                .copyWith(
                              color: InterceptlyTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 12.0),
                      itemCount: filteredFrames.length,
                      itemBuilder: (context, index) {
                        final frame = filteredFrames[index];
                        return RealtimeFrameCard(
                          frame: frame,
                          isInspected: _inspectedFrameIds.contains(frame.id),
                          parsedJson:
                              tryParseJsonPayload(frame, _parsedJsonCache),
                          onToggleInspect: () => _toggleInspect(frame.id),
                          onCopy: () => _copyPayload(frame),
                          onEdit: () => _onEditFrame(frame),
                          onResend: () => _onResendFrame(frame),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        body,
        RealtimeChatBar(
          sessionId: widget.sessionId,
          session: widget.session,
          textController: _chatController,
          eventController: _eventController,
          onSend: _sendMessage,
          onExpand: _onExpandComposer,
        ),
      ],
    );
  }
}
