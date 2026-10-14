import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:interceptly/src/model/realtime_protocol_type.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

/// Full modal sheet for composing multiline text or formatted JSON messages.
class RealtimeMessageComposerSheet extends StatefulWidget {
  /// Realtime protocol type for this connection.
  final RealtimeProtocolType protocolType;

  /// Initial event name if editing an existing message (Socket.IO).
  final String? initialEvent;

  /// Initial message payload text.
  final String? initialPayload;

  /// Async callback executed when the send button is tapped.
  final Future<void> Function(RealtimeMessageDraft draft) onSend;

  const RealtimeMessageComposerSheet({
    super.key,
    this.protocolType = RealtimeProtocolType.webSocket,
    this.initialEvent,
    this.initialPayload,
    required this.onSend,
  });

  @override
  State<RealtimeMessageComposerSheet> createState() =>
      _RealtimeMessageComposerSheetState();
}

class _RealtimeMessageComposerSheetState
    extends State<RealtimeMessageComposerSheet> {
  late final TextEditingController _eventController;
  late final TextEditingController _payloadController;
  String? _jsonWarning;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _eventController =
        TextEditingController(text: widget.initialEvent ?? '');
    _payloadController =
        TextEditingController(text: widget.initialPayload ?? '');
  }

  @override
  void dispose() {
    _eventController.dispose();
    _payloadController.dispose();
    super.dispose();
  }

  void _formatJson() {
    setState(() => _jsonWarning = null);
    final raw = _payloadController.text.trim();
    if (raw.isEmpty) return;
    try {
      final dynamic decoded = jsonDecode(raw);
      final formatted = const JsonEncoder.withIndent('  ').convert(decoded);
      _payloadController.text = formatted;
    } catch (e) {
      setState(() {
        _jsonWarning = 'Invalid JSON: $e';
      });
    }
  }

  Future<void> _handleSend() async {
    final payload = _payloadController.text;
    final isSocketIo = widget.protocolType == RealtimeProtocolType.socketIo;
    final event = isSocketIo ? _eventController.text.trim() : null;

    setState(() => _isSending = true);
    try {
      final draft = RealtimeMessageDraft(
        event: event?.isEmpty ?? true ? null : event,
        payload: payload,
      );
      await widget.onSend(draft);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSocketIo = widget.protocolType == RealtimeProtocolType.socketIo;
    final protocolName = isSocketIo ? 'Socket.IO' : 'WebSocket';

    return Container(
      key: const ValueKey('realtime_composer_sheet'),
      decoration: BoxDecoration(
        color: InterceptlyTheme.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(InterceptlyTheme.radius.lg),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: InterceptlyTheme.indigo500.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(
                              InterceptlyTheme.radius.sm),
                        ),
                        child: Text(
                          protocolName.toUpperCase(),
                          style: InterceptlyTheme.typography
                              .monospace(InterceptlyTheme.typography.bodySmallMedium)
                              .copyWith(color: InterceptlyTheme.indigo500),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Message Composer',
                        style: InterceptlyTheme.typography.bodyMediumBold
                            .copyWith(color: InterceptlyTheme.textPrimary),
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('realtime_composer_format_button'),
                    onPressed: _formatJson,
                    icon: const Icon(Icons.data_object, size: 14),
                    label: const Text('Format JSON'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      textStyle: InterceptlyTheme.typography.bodySmallMedium,
                      foregroundColor: InterceptlyTheme.textSecondary,
                      side: BorderSide(color: InterceptlyTheme.dividerSubtle),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Event Name (if Socket.IO)
              if (isSocketIo) ...[
                Text(
                  'Event Name',
                  style: InterceptlyTheme.typography.bodySmallMedium
                      .copyWith(color: InterceptlyTheme.textSecondary),
                ),
                const SizedBox(height: 4),
                TextField(
                  key: const ValueKey('realtime_composer_event_input'),
                  controller: _eventController,
                  style: InterceptlyTheme.typography
                      .monospace(InterceptlyTheme.typography.bodySmallRegular)
                      .copyWith(color: InterceptlyTheme.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'e.g. chat_message',
                    hintStyle: InterceptlyTheme.typography.bodySmallRegular
                        .copyWith(color: InterceptlyTheme.textMuted),
                    filled: true,
                    fillColor: InterceptlyTheme.surfaceContainer,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(InterceptlyTheme.radius.sm),
                      borderSide:
                          BorderSide(color: InterceptlyTheme.dividerSubtle),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(InterceptlyTheme.radius.sm),
                      borderSide:
                          BorderSide(color: InterceptlyTheme.dividerSubtle),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // JSON warning
              if (_jsonWarning != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: InterceptlyTheme.red500.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(InterceptlyTheme.radius.sm),
                    border: Border.all(
                      color: InterceptlyTheme.red500.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 14, color: InterceptlyTheme.red500),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _jsonWarning!,
                          style: InterceptlyTheme.typography.bodySmallRegular
                              .copyWith(color: InterceptlyTheme.red500),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Payload input
              Text(
                'Payload (JSON or Text)',
                style: InterceptlyTheme.typography.bodySmallMedium
                    .copyWith(color: InterceptlyTheme.textSecondary),
              ),
              const SizedBox(height: 4),
              TextField(
                key: const ValueKey('realtime_composer_payload_input'),
                controller: _payloadController,
                minLines: 8,
                maxLines: 16,
                keyboardType: TextInputType.multiline,
                style: InterceptlyTheme.typography
                    .monospace(InterceptlyTheme.typography.bodySmallRegular)
                    .copyWith(color: InterceptlyTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: '{\n  "key": "value"\n}',
                  hintStyle: InterceptlyTheme.typography
                      .monospace(InterceptlyTheme.typography.bodySmallRegular)
                      .copyWith(color: InterceptlyTheme.textMuted),
                  filled: true,
                  fillColor: InterceptlyTheme.surfaceContainer,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(InterceptlyTheme.radius.sm),
                    borderSide:
                        BorderSide(color: InterceptlyTheme.dividerSubtle),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(InterceptlyTheme.radius.sm),
                    borderSide:
                        BorderSide(color: InterceptlyTheme.dividerSubtle),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    key: const ValueKey('realtime_composer_cancel_button'),
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: InterceptlyTheme.textSecondary,
                      side: BorderSide(color: InterceptlyTheme.dividerSubtle),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const ValueKey('realtime_composer_send_button'),
                    onPressed: _isSending ? null : _handleSend,
                    icon: _isSending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Send'),
                    style: FilledButton.styleFrom(
                      backgroundColor: InterceptlyTheme.indigo500,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
