import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';

class _KeyValuePair {
  _KeyValuePair({
    required String key,
    required String value,
    required this.enabled,
  })  : keyController = TextEditingController(text: key),
        valueController = TextEditingController(text: value);

  final TextEditingController keyController;
  final TextEditingController valueController;
  bool enabled;

  String get key => keyController.text;
  String get value => valueController.text;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

class CustomRequestPage extends StatefulWidget {
  final String initialMethod;
  final String initialBaseUrl;
  final String initialQueryText;
  final String initialHeadersText;
  final String initialBodyText;

  const CustomRequestPage({
    super.key,
    required this.initialMethod,
    required this.initialBaseUrl,
    required this.initialQueryText,
    required this.initialHeadersText,
    required this.initialBodyText,
  });

  @override
  State<CustomRequestPage> createState() => _CustomRequestPageState();
}

class _CustomRequestPageState extends State<CustomRequestPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _methodController;
  late final TextEditingController _baseUrlController;
  late final _JsonSyntaxController _bodyController;

  late List<_KeyValuePair> _params;
  late List<_KeyValuePair> _headers;

  static const _methods = [
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'HEAD',
    'OPTIONS',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _methodController = TextEditingController(text: widget.initialMethod);
    _baseUrlController = TextEditingController(text: widget.initialBaseUrl);
    _bodyController = _JsonSyntaxController(text: widget.initialBodyText);

    _params = _parseQueryParams(widget.initialQueryText);
    _headers = _parseHeadersMap(widget.initialHeadersText);

    _methodController.addListener(_refresh);
    _baseUrlController.addListener(_refresh);
    _bodyController.addListener(_refresh);
  }

  @override
  void dispose() {
    _methodController.removeListener(_refresh);
    _baseUrlController.removeListener(_refresh);
    _bodyController.removeListener(_refresh);

    for (final p in _params) {
      p.dispose();
    }
    for (final h in _headers) {
      h.dispose();
    }

    _tabController.dispose();
    _methodController.dispose();
    _baseUrlController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  List<_KeyValuePair> _parseQueryParams(String raw) {
    final pairs = <_KeyValuePair>[];
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final idx = trimmed.indexOf('=');
      if (idx <= 0) {
        pairs.add(_KeyValuePair(key: trimmed, value: '', enabled: true));
        continue;
      }
      final key = trimmed.substring(0, idx).trim();
      final value = trimmed.substring(idx + 1).trim();
      if (key.isEmpty) continue;
      pairs.add(_KeyValuePair(key: key, value: value, enabled: true));
    }
    return pairs;
  }

  List<_KeyValuePair> _parseHeadersMap(String raw) {
    final pairs = <_KeyValuePair>[];
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return pairs;

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          pairs.add(_KeyValuePair(
            key: entry.key.toString(),
            value: entry.value.toString(),
            enabled: true,
          ));
        }
        return pairs;
      }
    } catch (_) {}

    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final idx = trimmed.indexOf(':');
      if (idx <= 0) continue;
      final key = trimmed.substring(0, idx).trim();
      final value = trimmed.substring(idx + 1).trim();
      if (key.isEmpty) continue;
      pairs.add(_KeyValuePair(key: key, value: value, enabled: true));
    }
    return pairs;
  }

  @override
  Widget build(BuildContext context) {
    final enabledParams = _params.where((p) => p.enabled).toList();
    final enabledHeaders = _headers.where((h) => h.enabled).toList();

    final jsonError = _validateJsonBody(_bodyController.text);

    return Scaffold(
      backgroundColor: InterceptlyTheme.surface,
      appBar: AppBar(
        backgroundColor: InterceptlyTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: InterceptlyTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Custom Request',
            style: InterceptlyTheme.typography.titleMediumBold.copyWith(
              color: InterceptlyTheme.textPrimary,
            )),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCard(
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<String>(
                      initialValue: _methods.contains(_methodController.text)
                          ? _methodController.text
                          : 'GET',
                      dropdownColor: InterceptlyTheme.surfaceContainer,
                      style: InterceptlyTheme.typography.bodyMediumRegular
                          .copyWith(color: InterceptlyTheme.textPrimary),
                      iconEnabledColor: InterceptlyTheme.textSecondary,
                      items: _methods
                          .map((m) => DropdownMenuItem<String>(
                                value: m,
                                child: Text(
                                  m,
                                  style: InterceptlyTheme
                                      .typography.bodyMediumRegular
                                      .copyWith(
                                    color: InterceptlyTheme.textPrimary,
                                    // fontSize: 13,
                                  ),
                                ),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        _methodController.text = value;
                      },
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        labelText: 'Method',
                        labelStyle: InterceptlyTheme
                            .typography.bodyMediumRegular
                            .copyWith(color: InterceptlyTheme.textMuted),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _baseUrlController,
                      decoration: InputDecoration(
                        labelText: 'URL',
                        labelStyle: InterceptlyTheme
                            .typography.bodyMediumRegular
                            .copyWith(color: InterceptlyTheme.textMuted),
                      ),
                      style: InterceptlyTheme.typography.bodyMediumRegular
                          .copyWith(color: InterceptlyTheme.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _buildCard(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TabBar(
                      controller: _tabController,
                      labelColor: InterceptlyTheme.indigo400,
                      unselectedLabelColor: InterceptlyTheme.textMuted,
                      indicatorColor: InterceptlyTheme.indigo500,
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Params'),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: InterceptlyTheme.indigo500
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  enabledParams.length.toString(),
                                  style: InterceptlyTheme
                                      .typography.bodyMediumRegular
                                      .copyWith(
                                    fontSize: 11,
                                    color: InterceptlyTheme.indigo400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Headers'),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: InterceptlyTheme.indigo500
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  enabledHeaders.length.toString(),
                                  style: InterceptlyTheme
                                      .typography.bodyMediumRegular
                                      .copyWith(
                                    fontSize: 11,
                                    color: InterceptlyTheme.indigo400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Tab(text: 'Body'),
                      ],
                    ),
                    Divider(height: 1, color: InterceptlyTheme.dividerSubtle),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildParamsTab(),
                          _buildHeadersTab(),
                          _buildBodyTab(jsonError),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                      padding: const EdgeInsets.symmetric(vertical: 0),
                      side: BorderSide(color: InterceptlyTheme.dividerSubtle),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: InterceptlyTheme.typography.labelMediumMedium
                          .copyWith(color: InterceptlyTheme.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: InterceptlyTheme.indigo500,
                      minimumSize: const Size.fromHeight(40),
                      padding: const EdgeInsets.symmetric(vertical: 0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      final currentQueryMap = <String, String>{};
                      for (final param in _params.where((p) => p.enabled)) {
                        if (param.key.isNotEmpty) {
                          currentQueryMap[param.key] = param.value;
                        }
                      }
                      final currentHeadersMap = <String, String>{};
                      for (final header in _headers.where((h) => h.enabled)) {
                        if (header.key.isNotEmpty) {
                          currentHeadersMap[header.key] = header.value;
                        }
                      }
                      final currentFullUrl = _composeUrl(
                          _baseUrlController.text.trim(), currentQueryMap);

                      Navigator.pop(
                        context,
                        CustomRequestDraft(
                          method: _methodController.text.trim().toUpperCase(),
                          url: currentFullUrl,
                          headers: currentHeadersMap,
                          body: _bodyController.text,
                        ),
                      );
                    },
                    child: Text(
                      'Send Request',
                      style: InterceptlyTheme.typography.labelMediumMedium
                          .copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParamsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 50,
                child: Text(
                  'KEY',
                  style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                    fontSize: 12,
                    color: InterceptlyTheme.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'VALUE',
                  style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                    fontSize: 12,
                    color: InterceptlyTheme.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 0,
          indent: 12,
          endIndent: 12,
          color: InterceptlyTheme.dividerSubtle,
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                ..._params.asMap().entries.map((entry) {
                  final pair = entry.value;
                  return _buildKeyValueRow(pair, () {
                    setState(() {
                      pair.enabled = !pair.enabled;
                    });
                  });
                }),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _params.add(_KeyValuePair(
                            key: '',
                            value: '',
                            enabled: true,
                          ));
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.add,
                              size: 20,
                              color: InterceptlyTheme.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'New Key',
                              style: InterceptlyTheme
                                  .typography.bodyMediumRegular
                                  .copyWith(
                                fontSize: 13,
                                color: InterceptlyTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeadersTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 50,
                child: Text(
                  'KEY',
                  style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                    fontSize: 12,
                    color: InterceptlyTheme.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'VALUE',
                  style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                    fontSize: 12,
                    color: InterceptlyTheme.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 0,
          indent: 12,
          endIndent: 12,
          color: InterceptlyTheme.dividerSubtle,
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                ..._headers.asMap().entries.map((entry) {
                  final pair = entry.value;
                  return _buildKeyValueRow(pair, () {
                    setState(() {
                      pair.enabled = !pair.enabled;
                    });
                  });
                }),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _headers.add(_KeyValuePair(
                            key: '',
                            value: '',
                            enabled: true,
                          ));
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.add,
                              size: 20,
                              color: InterceptlyTheme.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'New Header',
                              style: InterceptlyTheme
                                  .typography.bodyMediumRegular
                                  .copyWith(
                                fontSize: 13,
                                color: InterceptlyTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBodyTab(String? jsonError) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, left: 10, right: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RAW (JSON)',
                style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                  fontSize: 12,
                  color: InterceptlyTheme.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              TextButton.icon(
                onPressed: _formatJsonBody,
                label: const Text('Format JSON'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildLineNumbers(),
                Expanded(
                  child: TextField(
                    controller: _bodyController,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    decoration: const InputDecoration(
                      hintText: '{\n  "key": "value"\n}',
                      alignLabelWithHint: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    ),
                    style:
                        InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                      color: InterceptlyTheme.textPrimary,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (jsonError != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: _buildInlineError('Invalid JSON: $jsonError'),
          ),
        ],
      ],
    );
  }

  Widget _buildLineNumbers() {
    final lines = _bodyController.text.split('\n');
    final lineCount = lines.isEmpty ? 1 : lines.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      color: InterceptlyTheme.surface,
      child: Column(
        children: [
          SizedBox(
            height: 10,
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(
                  lineCount,
                  (idx) => Text(
                    '${idx + 1}',
                    style:
                        InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                      color: InterceptlyTheme.textMuted,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyValueRow(
    _KeyValuePair pair,
    VoidCallback onToggle,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: pair.enabled,
            onChanged: (_) => onToggle(),
            fillColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return InterceptlyTheme.indigo500;
              }
              return Colors.transparent;
            }),
            checkColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            side: BorderSide(
              color: pair.enabled
                  ? InterceptlyTheme.indigo500
                  : InterceptlyTheme.dividerSubtle,
              width: 1.5,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: InterceptlyTheme.dividerSubtle),
                borderRadius: BorderRadius.circular(6),
              ),
              child: TextField(
                controller: pair.keyController,
                enabled: pair.enabled,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Key',
                  hintStyle:
                      InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                    color: InterceptlyTheme.textMuted,
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                  color: pair.enabled
                      ? InterceptlyTheme.textPrimary
                      : InterceptlyTheme.textMuted,
                  fontSize: 13,
                  decoration: pair.enabled
                      ? TextDecoration.none
                      : TextDecoration.lineThrough,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: InterceptlyTheme.dividerSubtle),
                borderRadius: BorderRadius.circular(6),
              ),
              child: TextField(
                controller: pair.valueController,
                enabled: pair.enabled,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Value',
                  hintStyle:
                      InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                    color: InterceptlyTheme.textMuted,
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                  color: pair.enabled
                      ? InterceptlyTheme.textPrimary
                      : InterceptlyTheme.textMuted,
                  fontSize: 13,
                  decoration: pair.enabled
                      ? TextDecoration.none
                      : TextDecoration.lineThrough,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _composeUrl(String baseUrl, Map<String, String> queryParams) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) return baseUrl;
    return uri
        .replace(queryParameters: queryParams.isEmpty ? null : queryParams)
        .toString();
  }

  String? _validateJsonBody(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      jsonDecode(trimmed);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  void _formatJsonBody() {
    final trimmed = _bodyController.text.trim();
    if (trimmed.isEmpty) return;
    try {
      final decoded = jsonDecode(trimmed);
      _bodyController.text =
          const JsonEncoder.withIndent('  ').convert(decoded);
      _bodyController.selection = TextSelection.collapsed(
        offset: _bodyController.text.length,
      );
    } catch (_) {}
  }

  Widget _buildCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(10),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: InterceptlyTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: InterceptlyTheme.dividerSubtle),
      ),
      child: child,
    );
  }

  Widget _buildInlineError(String message) {
    return Text(
      message,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
        color: InterceptlyTheme.yellow400,
        fontSize: 11,
      ),
    );
  }
}

class CustomRequestDraft {
  const CustomRequestDraft({
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
  });

  final String method;
  final String url;
  final Map<String, String> headers;
  final String body;
}

class _JsonSyntaxController extends TextEditingController {
  _JsonSyntaxController({super.text});

  static const Color _keyColor = InterceptlyGlobalColor.blue400;
  static const Color _stringColor = InterceptlyGlobalColor.red400;
  static const Color _numberColor = InterceptlyGlobalColor.green400;
  static const Color _boolNullColor = InterceptlyGlobalColor.yellow400;
  static const Color _punctuationColor = InterceptlyGlobalColor.blue400;

  static final RegExp _tokenRegex = RegExp(
    r'"(?:\\.|[^"\\])*"|\btrue\b|\bfalse\b|\bnull\b|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|[{}\[\]:,]',
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ??
        InterceptlyTheme.typography.bodyMediumRegular.copyWith(
          color: InterceptlyTheme.textPrimary,
          fontSize: 13,
        );

    final textValue = text;
    if (textValue.isEmpty) {
      return TextSpan(style: baseStyle, text: textValue);
    }

    final spans = <TextSpan>[];
    var start = 0;

    for (final match in _tokenRegex.allMatches(textValue)) {
      if (match.start > start) {
        spans.add(TextSpan(
          text: textValue.substring(start, match.start),
          style: baseStyle,
        ));
      }

      final token = match.group(0)!;
      spans.add(TextSpan(
        text: token,
        style: baseStyle.copyWith(color: _colorForToken(token, match.end)),
      ));
      start = match.end;
    }

    if (start < textValue.length) {
      spans.add(TextSpan(text: textValue.substring(start), style: baseStyle));
    }

    return TextSpan(style: baseStyle, children: spans);
  }

  Color _colorForToken(String token, int tokenEnd) {
    if (token.isEmpty) return InterceptlyTheme.textPrimary;

    final first = token.codeUnitAt(0);
    if (first == 0x22) {
      var i = tokenEnd;
      while (i < text.length && _isWhitespace(text.codeUnitAt(i))) {
        i++;
      }
      final isKey = i < text.length && text.codeUnitAt(i) == 0x3A;
      return isKey ? _keyColor : _stringColor;
    }

    if (token == 'true' || token == 'false' || token == 'null') {
      return _boolNullColor;
    }

    if ((first >= 0x30 && first <= 0x39) || first == 0x2D) {
      return _numberColor;
    }

    if ('{}[]:,'.contains(token)) {
      return _punctuationColor;
    }

    return InterceptlyTheme.textPrimary;
  }

  bool _isWhitespace(int codeUnit) {
    return codeUnit == 0x20 ||
        codeUnit == 0x09 ||
        codeUnit == 0x0A ||
        codeUnit == 0x0D;
  }
}
