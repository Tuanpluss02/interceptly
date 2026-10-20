import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/realtime_frame.dart';
import '../../scope/interceptly_scope.dart';
import '../../interceptly_theme.dart';
import '../../widgets/json_viewer/json_viewer.dart';

import 'bounded_lru_cache.dart';
import 'realtime_formatters.dart';

/// Renders the expanded or collapsed payload of a [RealtimeFrame].
///
/// When collapsed, renders [RealtimeFrame.shortPreview] with zero disk I/O and zero JSON parsing.
/// When expanded / inspected:
/// - If [frame.location] is [BodyLocation.file], asynchronously fetches the full payload
///   via [InterceptlyScopeController.loadRealtimePayload], displaying a loading indicator while awaiting.
/// - Parses JSON lazily and caches parsed trees in [jsonCache].
class RealtimePayloadView extends StatefulWidget {
  final RealtimeFrame frame;
  final bool isInspected;
  final dynamic parsedJson;
  final VoidCallback onToggleInspect;
  final BoundedLruCache<String, dynamic>? jsonCache;

  const RealtimePayloadView({
    super.key,
    required this.frame,
    required this.isInspected,
    required this.parsedJson,
    required this.onToggleInspect,
    this.jsonCache,
  });

  @override
  State<RealtimePayloadView> createState() => _RealtimePayloadViewState();
}

class _RealtimePayloadViewState extends State<RealtimePayloadView> {
  bool _isLoading = false;
  bool _hasLoaded = false;
  bool _showHex = false;
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
      _showHex = false;
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
    final scope = InterceptlyScope.maybeRead(context);
    final requestedFrameId = widget.frame.id;

    if (scope == null) {
      setState(() {
        _isLoading = false;
        _hasLoaded = true;
        _loadedPayload = '[Payload unavailable: no scope]';
        _loadedJson = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    scope.loadRealtimePayload(widget.frame).then((payload) {
      if (!mounted || widget.frame.id != requestedFrameId) return;
      dynamic parsed;
      String? textToParse;
      if (payload is String && payload.trim().isNotEmpty) {
        textToParse = payload;
      } else if (payload is Uint8List) {
        textToParse = tryDecodeBinaryToText(payload);
      }

      if (textToParse != null && textToParse.trim().isNotEmpty) {
        if (widget.jsonCache != null &&
            widget.jsonCache!.containsKey(requestedFrameId)) {
          parsed = widget.jsonCache![requestedFrameId];
        } else {
          try {
            parsed = jsonDecode(textToParse);
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

  Widget _buildHeader({
    required bool isJson,
    bool isDecodableBinary = false,
    bool showHex = false,
    VoidCallback? onToggleHex,
  }) {
    final String label;
    if (widget.frame.isBinary) {
      if (showHex) {
        label = 'HEX PAYLOAD';
      } else if (isJson) {
        label = 'JSON (DECODED)';
      } else if (isDecodableBinary) {
        label = 'DECODED TEXT';
      } else {
        label = 'RAW BINARY';
      }
    } else {
      label = isJson ? 'JSON PAYLOAD' : 'RAW PAYLOAD';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
                color: InterceptlyTheme.textMuted,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
            if (isDecodableBinary) ...[
              const SizedBox(width: 8),
              InkWell(
                key: ValueKey('frame_toggle_decoded_${widget.frame.id}'),
                onTap: showHex ? onToggleHex : null,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: !showHex
                        ? InterceptlyTheme.indigo500.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: !showHex
                          ? InterceptlyTheme.indigo400.withValues(alpha: 0.4)
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    isJson ? 'JSON' : 'Text',
                    style:
                        InterceptlyTheme.typography.labelSmallMedium.copyWith(
                      fontSize: 10,
                      color: !showHex
                          ? InterceptlyTheme.indigo400
                          : InterceptlyTheme.textMuted,
                      fontWeight:
                          !showHex ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                key: ValueKey('frame_toggle_hex_${widget.frame.id}'),
                onTap: !showHex ? onToggleHex : null,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: showHex
                        ? InterceptlyTheme.indigo500.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: showHex
                          ? InterceptlyTheme.indigo400.withValues(alpha: 0.4)
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    'Hex',
                    style:
                        InterceptlyTheme.typography.labelSmallMedium.copyWith(
                      fontSize: 10,
                      color: showHex
                          ? InterceptlyTheme.indigo400
                          : InterceptlyTheme.textMuted,
                      fontWeight: showHex ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ],
          ],
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
              _buildHeader(isJson: false),
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

        final String? decodedText;
        if (_loadedPayload is Uint8List) {
          decodedText = tryDecodeBinaryToText(_loadedPayload as Uint8List);
        } else if (_loadedPayload is String) {
          decodedText = _loadedPayload as String;
        } else {
          decodedText = null;
        }

        final bool isDecodableBinary = widget.frame.isBinary &&
            _loadedPayload is Uint8List &&
            decodedText != null;

        final parsed = _loadedJson ?? widget.parsedJson;
        final bool showJson = !_showHex && parsed != null;

        final String displayText;
        if (_loadedPayload is Uint8List) {
          if (!_showHex && decodedText != null) {
            displayText = decodedText;
          } else {
            displayText = formatBinaryPreview(_loadedPayload as Uint8List);
          }
        } else if (_loadedPayload != null) {
          displayText = _loadedPayload.toString();
        } else {
          displayText = widget.frame.shortPreview;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(
              isJson: parsed != null,
              isDecodableBinary: isDecodableBinary,
              showHex: _showHex,
              onToggleHex: () => setState(() => _showHex = !_showHex),
            ),
            const SizedBox(height: 8),
            showJson
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
      final String? decodedBinaryText = widget.frame.binaryPayload != null
          ? tryDecodeBinaryToText(widget.frame.binaryPayload!)
          : null;
      final bool isDecodableBinary =
          widget.frame.isBinary && decodedBinaryText != null;

      dynamic effectiveJson = widget.parsedJson;
      if (effectiveJson == null && widget.jsonCache != null) {
        effectiveJson = tryParseJsonPayload(widget.frame, widget.jsonCache!);
      }

      final bool showJson = !_showHex && effectiveJson != null;
      final String displayText;
      if (_showHex && widget.frame.binaryPayload != null) {
        displayText = formatBinaryPreview(widget.frame.binaryPayload!);
      } else if (decodedBinaryText != null) {
        displayText = decodedBinaryText;
      } else {
        displayText = getFramePayloadString(widget.frame);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(
            isJson: effectiveJson != null,
            isDecodableBinary: isDecodableBinary,
            showHex: _showHex,
            onToggleHex: () => setState(() => _showHex = !_showHex),
          ),
          const SizedBox(height: 8),
          showJson
              ? JsonViewer(data: effectiveJson)
              : SelectableText(
                  displayText,
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
