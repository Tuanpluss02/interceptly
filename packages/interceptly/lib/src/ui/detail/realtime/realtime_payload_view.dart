import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/realtime_frame.dart';
import 'package:interceptly/src/session/inspector_session_view.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';

import 'bounded_lru_cache.dart';
import 'realtime_formatters.dart';

/// Renders the expanded or collapsed payload of a [RealtimeFrame].
///
/// When collapsed, renders [RealtimeFrame.shortPreview] with zero disk I/O and zero JSON parsing.
/// When expanded / inspected:
/// - If [frame.location] is [BodyLocation.file], asynchronously fetches the full payload
///   via [session.loadRealtimePayload], displaying a loading indicator while awaiting.
/// - Parses JSON lazily and caches parsed trees in [jsonCache].
class RealtimePayloadView extends StatefulWidget {
  final RealtimeFrame frame;
  final bool isInspected;
  final dynamic parsedJson;
  final VoidCallback onToggleInspect;
  final InspectorSessionView? session;
  final BoundedLruCache<String, dynamic>? jsonCache;

  const RealtimePayloadView({
    super.key,
    required this.frame,
    required this.isInspected,
    required this.parsedJson,
    required this.onToggleInspect,
    this.session,
    this.jsonCache,
  });

  @override
  State<RealtimePayloadView> createState() => _RealtimePayloadViewState();
}

class _RealtimePayloadViewState extends State<RealtimePayloadView> {
  bool _isLoading = false;
  bool _hasLoaded = false;
  dynamic _loadedPayload;
  dynamic _loadedJson;

  @override
  void initState() {
    super.initState();
    _checkLoadPayload();
  }

  @override
  void didUpdateWidget(covariant RealtimePayloadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.frame.id != oldWidget.frame.id) {
      _loadedPayload = null;
      _loadedJson = null;
      _isLoading = false;
      _hasLoaded = false;
    }
    _checkLoadPayload();
  }

  void _checkLoadPayload() {
    if (widget.isInspected &&
        widget.frame.location == BodyLocation.file &&
        !_hasLoaded &&
        !_isLoading) {
      _fetchPayload();
    }
  }

  void _fetchPayload() {
    final session = widget.session;
    final requestedFrameId = widget.frame.id;

    if (session == null) {
      setState(() {
        _isLoading = false;
        _hasLoaded = true;
        _loadedPayload = '[Payload unavailable: no session]';
        _loadedJson = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    session.loadRealtimePayload(widget.frame).then((payload) {
      if (!mounted || widget.frame.id != requestedFrameId) return;
      dynamic parsed;
      if (payload is String && payload.trim().isNotEmpty) {
        if (widget.jsonCache != null &&
            widget.jsonCache!.containsKey(requestedFrameId)) {
          parsed = widget.jsonCache![requestedFrameId];
        } else {
          try {
            parsed = jsonDecode(payload);
            widget.jsonCache?[requestedFrameId] = parsed;
          } catch (_) {
            widget.jsonCache?[requestedFrameId] = null;
          }
        }
      }
      setState(() {
        _isLoading = false;
        _hasLoaded = true;
        _loadedPayload = payload;
        _loadedJson = parsed;
      });
    }).catchError((e) {
      if (!mounted || widget.frame.id != requestedFrameId) return;
      setState(() {
        _isLoading = false;
        _hasLoaded = true;
        _loadedPayload = '[Error loading payload: $e]';
        _loadedJson = null;
      });
    });
  }

  Widget _buildHeader(bool isJson) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          isJson ? 'JSON PAYLOAD' : 'RAW PAYLOAD',
          style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
            color: InterceptlyTheme.textMuted,
            fontSize: 10,
            letterSpacing: 0.5,
          ),
        ),
        GestureDetector(
          key: ValueKey('frame_collapse_${widget.frame.id}'),
          onTap: widget.onToggleInspect,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Collapse',
                style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isInspected) {
      if (widget.frame.location == BodyLocation.file) {
        if (_isLoading) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(false),
              const SizedBox(height: 16),
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      InterceptlyTheme.indigo400,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
        }

        final parsed = _loadedJson ?? widget.parsedJson;
        final String displayText;
        if (_loadedPayload is Uint8List) {
          displayText = formatBinaryPreview(_loadedPayload as Uint8List);
        } else if (_loadedPayload != null) {
          displayText = _loadedPayload.toString();
        } else {
          displayText = widget.frame.shortPreview;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(parsed != null),
            const SizedBox(height: 8),
            parsed != null
                ? JsonViewer(data: parsed)
                : SelectableText(
                    displayText,
                    style:
                        InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                      fontSize: 12,
                      color: InterceptlyTheme.textPrimary,
                    ),
                  ),
          ],
        );
      }

      // In-memory frame
      dynamic effectiveJson = widget.parsedJson;
      if (effectiveJson == null && widget.jsonCache != null) {
        effectiveJson = tryParseJsonPayload(widget.frame, widget.jsonCache!);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(effectiveJson != null),
          const SizedBox(height: 8),
          effectiveJson != null
              ? JsonViewer(data: effectiveJson)
              : SelectableText(
                  getFramePayloadString(widget.frame),
                  style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                    fontSize: 12,
                    color: InterceptlyTheme.textPrimary,
                  ),
                ),
        ],
      );
    }

    // Collapsed card: display frame.shortPreview with NO disk reads or JSON parsing
    return InkWell(
      key: ValueKey('frame_payload_${widget.frame.id}'),
      borderRadius: BorderRadius.vertical(
        bottom: Radius.circular(InterceptlyTheme.radius.md),
      ),
      onTap: widget.onToggleInspect,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              widget.frame.shortPreview,
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
