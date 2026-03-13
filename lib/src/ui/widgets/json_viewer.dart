import 'package:flutter/material.dart';

class JsonViewer extends StatefulWidget {
  final dynamic data;

  const JsonViewer({super.key, required this.data});

  @override
  State<JsonViewer> createState() => _JsonViewerState();
}

class _JsonViewerState extends State<JsonViewer> {
  // Theme colors matching UI.html
  static const _keyColor = Color(0xFF9CDCFE);
  static const _stringColor = Color(0xFFCE9178);
  static const _numberColor = Color(0xFFB5CEA8);
  static const _boolColor = Color(0xFF569CD6);
  static const _nullColor = Color(0xFF569CD6);
  static const _punctuationColor = Color(0xFF9CA3AF); // gray-400

  @override
  Widget build(BuildContext context) {
    if (widget.data == null) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text(
          'No Data',
          style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.5,
        ),
        child: _JsonNode(
          nodeKey: null,
          value: widget.data,
          isLast: true,
          root: true,
        ),
      ),
    );
  }
}

class _JsonNode extends StatefulWidget {
  final String? nodeKey;
  final dynamic value;
  final bool isLast;
  final bool root;

  const _JsonNode({
    this.nodeKey,
    required this.value,
    this.isLast = false,
    this.root = false,
  });

  @override
  State<_JsonNode> createState() => _JsonNodeState();
}

class _JsonNodeState extends State<_JsonNode> {
  bool _isExpanded = true;

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyHtml = widget.nodeKey != null
        ? TextSpan(children: [
            TextSpan(
                text: '"${widget.nodeKey}"',
                style: const TextStyle(color: _JsonViewerState._keyColor)),
            const TextSpan(
                text: ': ',
                style: TextStyle(color: _JsonViewerState._punctuationColor)),
          ])
        : const TextSpan();

    final comma = widget.isLast
        ? const TextSpan()
        : const TextSpan(
            text: ',',
            style: TextStyle(color: _JsonViewerState._punctuationColor));

    if (widget.value == null) {
      return _buildLine(keyHtml, const TextSpan(text: 'null', style: TextStyle(color: _JsonViewerState._nullColor)), comma);
    }
    if (widget.value is bool) {
      return _buildLine(keyHtml, TextSpan(text: widget.value.toString(), style: const TextStyle(color: _JsonViewerState._boolColor)), comma);
    }
    if (widget.value is num) {
      return _buildLine(keyHtml, TextSpan(text: widget.value.toString(), style: const TextStyle(color: _JsonViewerState._numberColor)), comma);
    }
    if (widget.value is String) {
      return _buildLine(keyHtml, TextSpan(text: '"${widget.value}"', style: const TextStyle(color: _JsonViewerState._stringColor)), comma);
    }

    if (widget.value is List) {
      final list = widget.value as List;
      if (list.isEmpty) {
        return _buildLine(keyHtml, const TextSpan(text: '[]', style: TextStyle(color: _JsonViewerState._punctuationColor)), comma);
      }
      return _buildCollapsible(
          keyHtml: keyHtml,
          openBracket: '[',
          closeBracket: ']',
          comma: comma,
          children: list.asMap().entries.map((e) => _JsonNode(
                value: e.value,
                isLast: e.key == list.length - 1,
              )).toList(),
      );
    }

    if (widget.value is Map) {
      final map = widget.value as Map;
      if (map.isEmpty) {
        return _buildLine(keyHtml, const TextSpan(text: '{}', style: TextStyle(color: _JsonViewerState._punctuationColor)), comma);
      }
      final entries = map.entries.toList();
      return _buildCollapsible(
        keyHtml: keyHtml,
        openBracket: '{',
        closeBracket: '}',
        comma: comma,
        children: entries.asMap().entries.map((e) => _JsonNode(
              nodeKey: e.value.key.toString(),
              value: e.value.value,
              isLast: e.key == entries.length - 1,
            )).toList(),
      );
    }

    return _buildLine(keyHtml, TextSpan(text: widget.value.toString()), comma);
  }

  Widget _buildLine(TextSpan keySpan, TextSpan valueSpan, TextSpan commaSpan) {
    return Padding(
      padding: EdgeInsets.only(left: widget.root ? 0 : 16.0),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [keySpan, valueSpan, commaSpan],
        ),
      ),
    );
  }

  Widget _buildCollapsible({
    required TextSpan keyHtml,
    required String openBracket,
    required String closeBracket,
    required TextSpan comma,
    required List<Widget> children,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: widget.root ? 0 : 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggle,
            hoverColor: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.rotate(
                  angle: _isExpanded ? 0 : -1.5708, // 0 or -90 deg
                  child: const Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey),
                ),
                RichText(
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style,
                    children: [
                      keyHtml,
                      TextSpan(
                        text: openBracket,
                        style: const TextStyle(color: _JsonViewerState._punctuationColor),
                      ),
                      if (!_isExpanded)
                        const TextSpan(
                          text: ' ... ',
                          style: TextStyle(color: Colors.grey, fontSize: 10),
                        ),
                      if (!_isExpanded)
                        TextSpan(
                          text: closeBracket,
                          style: const TextStyle(color: _JsonViewerState._punctuationColor),
                        ),
                      if (!_isExpanded) comma,
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isExpanded)
            Container(
              margin: const EdgeInsets.only(left: 8.0),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1.0,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          if (_isExpanded)
            RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: closeBracket,
                    style: const TextStyle(color: _JsonViewerState._punctuationColor),
                  ),
                  comma,
                ],
              ),
            ),
        ],
      ),
    );
  }
}
