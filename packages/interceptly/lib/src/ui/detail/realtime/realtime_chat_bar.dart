import 'package:flutter/material.dart';
import 'package:interceptly/src/model/realtime_protocol_type.dart';
import 'package:interceptly/src/session/inspector_session_view.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

/// A bottom chat bar for sending messages to an active realtime connection.
///
/// Adapts its layout depending on the protocol type (e.g. WebSocket vs Socket.IO vs SSE)
/// and handles closed connection states gracefully.
class RealtimeChatBar extends StatefulWidget {
  /// Session ID of the active realtime connection.
  final String sessionId;

  /// Active inspector session providing connection state and protocol info.
  final InspectorSessionView? session;

  /// Explicit flag indicating whether sending is supported/allowed.
  /// If null, defaults to [session.canSendRealtimeMessage(sessionId)].
  final bool? canSend;

  /// Protocol type of the connection.
  /// If null, defaults to [session.getRealtimeProtocol(sessionId)].
  final RealtimeProtocolType? protocolType;

  /// Controller for the message payload.
  final TextEditingController textController;

  /// Controller for the Socket.IO event name.
  final TextEditingController? eventController;

  /// Callback executed when the send button is tapped.
  final VoidCallback onSend;

  /// Callback executed when the expand button is tapped.
  final VoidCallback onExpand;

  const RealtimeChatBar({
    super.key,
    required this.sessionId,
    this.session,
    this.canSend,
    this.protocolType,
    required this.textController,
    this.eventController,
    required this.onSend,
    required this.onExpand,
  });

  @override
  State<RealtimeChatBar> createState() => _RealtimeChatBarState();
}

class _RealtimeChatBarState extends State<RealtimeChatBar> {
  @override
  void initState() {
    super.initState();
    widget.textController.addListener(_onTextChanged);
    widget.eventController?.addListener(_onTextChanged);
    widget.session?.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(covariant RealtimeChatBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.textController != oldWidget.textController) {
      oldWidget.textController.removeListener(_onTextChanged);
      widget.textController.addListener(_onTextChanged);
    }
    if (widget.eventController != oldWidget.eventController) {
      oldWidget.eventController?.removeListener(_onTextChanged);
      widget.eventController?.addListener(_onTextChanged);
    }
    if (widget.session != oldWidget.session) {
      oldWidget.session?.removeListener(_onSessionChanged);
      widget.session?.addListener(_onSessionChanged);
    }
  }

  @override
  void dispose() {
    widget.textController.removeListener(_onTextChanged);
    widget.eventController?.removeListener(_onTextChanged);
    widget.session?.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  bool get _effectiveCanSend =>
      widget.canSend ??
      widget.session?.canSendRealtimeMessage(widget.sessionId) ??
      false;

  RealtimeProtocolType get _effectiveProtocol =>
      widget.protocolType ??
      widget.session?.getRealtimeProtocol(widget.sessionId) ??
      RealtimeProtocolType.webSocket;

  bool get _isSendEnabled {
    if (!_effectiveCanSend) return false;
    final text = widget.textController.text.trim();
    return text.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _effectiveCanSend;
    final protocol = _effectiveProtocol;
    final isSocketIo = protocol == RealtimeProtocolType.socketIo;
    final isSse = protocol == RealtimeProtocolType.sse;

    final closedNotice = isSse
        ? 'Server-Sent Events is a read-only stream'
        : 'Connection is closed';

    return Container(
      decoration: BoxDecoration(
        color: InterceptlyTheme.surfaceContainer,
        border: Border(
          top: BorderSide(
            color: InterceptlyTheme.dividerSubtle,
            width: 1.0,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!canSend)
              Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: InterceptlyTheme.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      closedNotice,
                      style: InterceptlyTheme.typography.bodySmallRegular.copyWith(
                        color: InterceptlyTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (canSend && isSocketIo) ...[
                  SizedBox(
                    width: 120,
                    child: TextField(
                      key: const ValueKey('realtime_chat_event_input'),
                      controller: widget.eventController,
                      enabled: canSend,
                      style: InterceptlyTheme.typography.bodySmallRegular.copyWith(
                        color: InterceptlyTheme.textPrimary,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Event name',
                        hintStyle: InterceptlyTheme.typography.bodySmallRegular.copyWith(
                          color: InterceptlyTheme.textMuted,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        filled: true,
                        fillColor: InterceptlyTheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(InterceptlyTheme.radius.sm),
                          borderSide: BorderSide(color: InterceptlyTheme.dividerSubtle),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(InterceptlyTheme.radius.sm),
                          borderSide: BorderSide(color: InterceptlyTheme.dividerSubtle),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: TextField(
                    key: const ValueKey('realtime_chat_input'),
                    controller: widget.textController,
                    enabled: canSend,
                    minLines: 1,
                    maxLines: 4,
                    style: InterceptlyTheme.typography.bodySmallRegular.copyWith(
                      color: InterceptlyTheme.textPrimary,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Send message or JSON...',
                      hintStyle: InterceptlyTheme.typography.bodySmallRegular.copyWith(
                        color: InterceptlyTheme.textMuted,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      filled: true,
                      fillColor: InterceptlyTheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(InterceptlyTheme.radius.sm),
                        borderSide: BorderSide(color: InterceptlyTheme.dividerSubtle),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(InterceptlyTheme.radius.sm),
                        borderSide: BorderSide(color: InterceptlyTheme.dividerSubtle),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(InterceptlyTheme.radius.sm),
                        borderSide: BorderSide(color: InterceptlyTheme.dividerSubtle),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  key: const ValueKey('realtime_chat_expand_button'),
                  icon: const Icon(Icons.open_in_full, size: 18),
                  tooltip: 'Expand multiline composer',
                  color: canSend
                      ? InterceptlyTheme.textSecondary
                      : InterceptlyTheme.textMuted,
                  onPressed: widget.onExpand,
                ),
                IconButton(
                  key: const ValueKey('realtime_chat_send_button'),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  tooltip: 'Send',
                  color: _isSendEnabled
                      ? InterceptlyTheme.indigo500
                      : InterceptlyTheme.controlMuted,
                  onPressed: _isSendEnabled ? widget.onSend : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
