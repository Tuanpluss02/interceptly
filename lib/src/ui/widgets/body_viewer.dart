import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Smart body display widget that auto-detects content format and lets the
/// user toggle between Raw, Pretty, and Decoded views.
///
/// | Format detected | Raw | Pretty | Decoded |
/// |---|---|---|---|
/// | `application/json` | raw text | indented JSON | same as pretty |
/// | `application/x-www-form-urlencoded` | raw string | raw string | key=value table |
/// | binary / image | — | `[binary: N bytes]` | — |
/// | other text | raw text | raw text | raw text |
class BodyViewer extends StatefulWidget {
  const BodyViewer({
    super.key,
    required this.body,
    this.contentType,
    this.label,
  });

  final String? body;
  final String? contentType;

  /// Optional section label shown above the viewer (e.g. "Request body").
  final String? label;

  @override
  State<BodyViewer> createState() => _BodyViewerState();
}

enum _DisplayMode { raw, pretty, decoded }

class _BodyViewerState extends State<BodyViewer> {
  late _DisplayMode _mode;
  late _BodyKind _kind;
  // Cache the pretty-printed result so jsonDecode + JsonEncoder don't run
  // on every rebuild — computed once per body/mode change.
  String? _prettyCache;
  String? _prettyCacheInput;

  @override
  void initState() {
    super.initState();
    _kind = _detectKind(widget.contentType, widget.body);
    _mode = _defaultMode(_kind);
  }

  @override
  void didUpdateWidget(BodyViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body ||
        oldWidget.contentType != widget.contentType) {
      _kind = _detectKind(widget.contentType, widget.body);
      _mode = _defaultMode(_kind);
      _prettyCache = null;
      _prettyCacheInput = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = widget.body;

    if (body == null || body.isEmpty) {
      return const Text('(empty)', style: TextStyle(fontStyle: FontStyle.italic));
    }

    final displayText = _buildDisplayText(body, _mode, _kind);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (widget.label != null) ...[
              Text(widget.label!, style: theme.textTheme.labelLarge),
              const Spacer(),
            ],
            _ModeToggle(
              kind: _kind,
              selected: _mode,
              onChanged: (m) => setState(() => _mode = m),
            ),
            const SizedBox(width: 4),
            _CopyButton(text: displayText),
          ],
        ),
        const SizedBox(height: 8),
        if (_mode == _DisplayMode.decoded && _kind == _BodyKind.urlEncoded)
          _UrlEncodedTable(raw: body)
        else
          SelectableText(
            displayText,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
      ],
    );
  }

  String _buildDisplayText(String body, _DisplayMode mode, _BodyKind kind) {
    if (kind == _BodyKind.binary) return body;
    if (mode == _DisplayMode.raw) return body;

    if (kind == _BodyKind.json && mode != _DisplayMode.raw) {
      // Cache the result: jsonDecode + JsonEncoder can take 10–50 ms for
      // large payloads, so we compute it once and reuse on subsequent builds.
      if (_prettyCache != null && _prettyCacheInput == body) {
        return _prettyCache!;
      }
      try {
        final result =
            const JsonEncoder.withIndent('  ').convert(jsonDecode(body));
        _prettyCache = result;
        _prettyCacheInput = body;
        return result;
      } catch (_) {
        return body;
      }
    }

    return body;
  }
}

// ---------------------------------------------------------------------------
// Body kind detection
// ---------------------------------------------------------------------------

enum _BodyKind { json, urlEncoded, text, binary }

_BodyKind _detectKind(String? contentType, String? body) {
  if (body == null || body.isEmpty) return _BodyKind.text;

  final lower = contentType?.toLowerCase() ?? '';

  if (lower.contains('application/json') || lower.contains('+json')) {
    return _BodyKind.json;
  }
  if (lower.contains('application/x-www-form-urlencoded')) {
    return _BodyKind.urlEncoded;
  }
  if (body.startsWith('[binary:')) return _BodyKind.binary;

  // Heuristic: try to parse as JSON even without the header.
  if (body.trimLeft().startsWith('{') || body.trimLeft().startsWith('[')) {
    try {
      jsonDecode(body);
      return _BodyKind.json;
    } catch (_) {}
  }

  return _BodyKind.text;
}

_DisplayMode _defaultMode(_BodyKind kind) {
  return switch (kind) {
    _BodyKind.json => _DisplayMode.pretty,
    _BodyKind.urlEncoded => _DisplayMode.decoded,
    _ => _DisplayMode.raw,
  };
}

// ---------------------------------------------------------------------------
// Mode toggle chip row
// ---------------------------------------------------------------------------

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.kind,
    required this.selected,
    required this.onChanged,
  });

  final _BodyKind kind;
  final _DisplayMode selected;
  final ValueChanged<_DisplayMode> onChanged;

  @override
  Widget build(BuildContext context) {
    if (kind == _BodyKind.binary || kind == _BodyKind.text) {
      return const SizedBox.shrink();
    }

    final modes = <_DisplayMode>[
      _DisplayMode.raw,
      _DisplayMode.pretty,
      if (kind == _BodyKind.urlEncoded) _DisplayMode.decoded,
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: modes.map((m) {
        final label = switch (m) {
          _DisplayMode.raw => 'Raw',
          _DisplayMode.pretty => 'Pretty',
          _DisplayMode.decoded => 'Decoded',
        };
        final isSelected = m == selected;
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: ChoiceChip(
            label: Text(label),
            selected: isSelected,
            onSelected: (_) => onChanged(m),
            labelStyle: const TextStyle(fontSize: 11),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: VisualDensity.compact,
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// URL-encoded key=value table
// ---------------------------------------------------------------------------

class _UrlEncodedTable extends StatelessWidget {
  const _UrlEncodedTable({required this.raw});

  final String raw;

  @override
  Widget build(BuildContext context) {
    final Map<String, String> params;
    try {
      params = Uri.splitQueryString(raw);
    } catch (_) {
      return SelectableText(raw);
    }

    if (params.isEmpty) {
      return const Text('(empty)', style: TextStyle(fontStyle: FontStyle.italic));
    }

    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(),
      },
      border: TableBorder.all(
        color: Colors.grey.withValues(alpha: 0.3),
        width: 0.5,
      ),
      children: params.entries.map((e) {
        return TableRow(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(6),
              child: SelectableText(
                e.key,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: SelectableText(
                e.value,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Copy button
// ---------------------------------------------------------------------------

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});

  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      tooltip: _copied ? 'Copied!' : 'Copy',
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: widget.text));
        if (!mounted) return;
        setState(() => _copied = true);
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _copied = false);
      },
      icon: Icon(
        _copied ? Icons.check : Icons.copy_outlined,
        color: _copied ? Colors.green : null,
      ),
    );
  }
}
