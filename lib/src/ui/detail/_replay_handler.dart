import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../capture/http/interceptly_http_client.dart';
import '../../model/request_record.dart';
import '../../storage/inspector_session.dart';
import '../interceptly_theme.dart';
import '../widgets/toast_notification.dart';

class ReplayHandler {
  const ReplayHandler({
    required this.context,
    required this.session,
  });

  final BuildContext context;
  final InspectorSession session;

  void showReplayMenu(RequestRecord record) {
    showModalBottomSheet(
      context: context,
      backgroundColor: InterceptlyTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading:
                  const Icon(Icons.refresh, color: InterceptlyTheme.indigo500),
              title: const Text('Retry Request'),
              subtitle: const Text('Send the same request again',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(context);
                retry(record);
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading:
                  const Icon(Icons.edit_note, color: InterceptlyTheme.indigo500),
              title: const Text('Duplicate & Edit'),
              subtitle: const Text('Modify request then send as new',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(context);
                duplicateAndEdit(record);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> retry(RequestRecord record) async {
    if (_isUnsupportedMethod(record.method)) {
      ToastNotification.show(
        context,
        'Retry is not supported for ${record.method}',
      );
      return;
    }

    await _sendRequest(
      method: record.method,
      url: record.url,
      headers: Map<String, String>.from(record.requestHeaders),
      body: record.requestBodyPreview,
      isBodyTruncated: record.isBodyTruncated,
    );
  }

  Future<void> duplicateAndEdit(RequestRecord record) async {
    if (_isUnsupportedMethod(record.method)) {
      ToastNotification.show(
        context,
        'Edit/Replay is not supported for ${record.method}',
      );
      return;
    }

    final (baseUrl, queryParams) = _splitUrlForEditing(record.url);

    final result = await showModalBottomSheet<_ReplayDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: InterceptlyTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return _ReplayEditorSheet(
          initialMethod: record.method.toUpperCase(),
          initialBaseUrl: baseUrl,
          initialQueryText: _queryParamsToText(queryParams),
          initialHeadersText: _headersToText(record.requestHeaders),
          initialBodyText: record.requestBodyPreview ?? '',
        );
      },
    );

    if (result == null) return;

    await _sendRequest(
      method: result.method,
      url: result.url,
      headers: result.headers,
      body: result.body,
      isBodyTruncated: record.isBodyTruncated,
    );
  }

  Future<void> _sendRequest({
    required String method,
    required String url,
    required Map<String, String> headers,
    required String? body,
    required bool isBodyTruncated,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      ToastNotification.show(context, 'Invalid URL');
      return;
    }

    if (_isUnsupportedMethod(method)) {
      ToastNotification.show(context, 'Unsupported method: $method');
      return;
    }

    final cleanedHeaders = _sanitizeReplayHeaders(headers);

    if (isBodyTruncated && body != null && body.isNotEmpty) {
      ToastNotification.show(context, 'Warning: body may be truncated');
    }

    final request = http.Request(method, uri);
    request.headers.addAll(cleanedHeaders);

    final upperMethod = method.toUpperCase();
    final allowBody =
        upperMethod != 'GET' && upperMethod != 'HEAD' && upperMethod != 'TRACE';

    if (allowBody && body != null && body.isNotEmpty) {
      request.bodyBytes = utf8.encode(body);
      request.headers.putIfAbsent(
        'content-type',
        () => 'application/json; charset=utf-8',
      );
    }

    final client = InterceptlyHttpClient.wrap(http.Client(), session);

    try {
      ToastNotification.show(context, 'Sending request...');
      final streamed = await client.send(request);
      await streamed.stream.drain<void>();
      if (!context.mounted) return;
      ToastNotification.show(context, 'Replay sent (${streamed.statusCode})');
    } catch (e) {
      if (!context.mounted) return;
      ToastNotification.show(context, 'Replay failed: $e');
    } finally {
      client.close();
    }
  }

  bool _isUnsupportedMethod(String method) {
    final m = method.toUpperCase();
    return m == 'WS';
  }

  Map<String, String> _sanitizeReplayHeaders(Map<String, String> headers) {
    final blocked = <String>{
      'host',
      'content-length',
      'connection',
      'accept-encoding',
      'transfer-encoding',
    };

    final result = <String, String>{};
    for (final entry in headers.entries) {
      final key = entry.key.trim();
      final value = entry.value;
      if (key.isEmpty) continue;
      if (blocked.contains(key.toLowerCase())) continue;
      result[key] = value;
    }
    return result;
  }

  String _headersToText(Map<String, String> headers) {
    return const JsonEncoder.withIndent('  ').convert(headers);
  }

  (String, Map<String, String>) _splitUrlForEditing(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return (url, const <String, String>{});
    }

    final baseUri = uri.replace(queryParameters: null);
    return (baseUri.toString(), Map<String, String>.from(uri.queryParameters));
  }

  String _queryParamsToText(Map<String, String> queryParams) {
    if (queryParams.isEmpty) return '';
    return queryParams.entries.map((e) => '${e.key}=${e.value}').join('\n');
  }
}

class _ReplayEditorSheet extends StatefulWidget {
  const _ReplayEditorSheet({
    required this.initialMethod,
    required this.initialBaseUrl,
    required this.initialQueryText,
    required this.initialHeadersText,
    required this.initialBodyText,
  });

  final String initialMethod;
  final String initialBaseUrl;
  final String initialQueryText;
  final String initialHeadersText;
  final String initialBodyText;

  @override
  State<_ReplayEditorSheet> createState() => _ReplayEditorSheetState();
}

class _ReplayEditorSheetState extends State<_ReplayEditorSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _methodController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _queryController;
  late final _JsonSyntaxController _headersController;
  late final _JsonSyntaxController _bodyController;

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
    _queryController = TextEditingController(text: widget.initialQueryText);
    _headersController = _JsonSyntaxController(text: widget.initialHeadersText);
    _bodyController = _JsonSyntaxController(text: widget.initialBodyText);

    _methodController.addListener(_refresh);
    _baseUrlController.addListener(_refresh);
    _queryController.addListener(_refresh);
    _headersController.addListener(_refresh);
    _bodyController.addListener(_refresh);
  }

  @override
  void dispose() {
    _methodController.removeListener(_refresh);
    _baseUrlController.removeListener(_refresh);
    _queryController.removeListener(_refresh);
    _headersController.removeListener(_refresh);
    _bodyController.removeListener(_refresh);

    _tabController.dispose();
    _methodController.dispose();
    _baseUrlController.dispose();
    _queryController.dispose();
    _headersController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Map<String, String> _parseQueryParams(String raw) {
    final map = <String, String>{};
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final idx = trimmed.indexOf('=');
      if (idx <= 0) {
        map[trimmed] = '';
        continue;
      }
      final key = trimmed.substring(0, idx).trim();
      final value = trimmed.substring(idx + 1).trim();
      if (key.isEmpty) continue;
      map[key] = value;
    }
    return map;
  }

  Map<String, String> _parseHeaders(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return <String, String>{};

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}

    final map = <String, String>{};
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final idx = trimmed.indexOf(':');
      if (idx <= 0) continue;
      final key = trimmed.substring(0, idx).trim();
      final value = trimmed.substring(idx + 1).trim();
      if (key.isEmpty) continue;
      map[key] = value;
    }
    return map;
  }

  String? _validateHeadersJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        return 'Headers must be a JSON object';
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  void _formatHeadersJson() {
    final trimmed = _headersController.text.trim();
    if (trimmed.isEmpty) return;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        _headersController.text =
            const JsonEncoder.withIndent('  ').convert(decoded);
        _headersController.selection = TextSelection.collapsed(
          offset: _headersController.text.length,
        );
      }
    } catch (_) {
      // keep original text when not valid JSON
    }
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
    } catch (_) {
      // keep original text when not valid JSON
    }
  }

  @override
  Widget build(BuildContext context) {
    final queryMap = _parseQueryParams(_queryController.text);
    final headersMap = _parseHeaders(_headersController.text);
    final fullUrl = _composeUrl(_baseUrlController.text.trim(), queryMap);
    final headersJsonError = _validateHeadersJson(_headersController.text);
    final jsonError = _validateJsonBody(_bodyController.text);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Request Editor',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: InterceptlyTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<String>(
                    initialValue: _methods.contains(_methodController.text)
                        ? _methodController.text
                        : 'GET',
                    items: _methods
                        .map((m) => DropdownMenuItem<String>(
                              value: m,
                              child: Text(m),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      _methodController.text = value;
                    },
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Method',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _baseUrlController,
                    decoration: const InputDecoration(
                      labelText: 'URL',
                      labelStyle: TextStyle(color: InterceptlyTheme.textMuted),
                    ),
                    style:
                        const TextStyle(color: InterceptlyTheme.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: InterceptlyTheme.surfaceContainer,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: InterceptlyTheme.indigo400,
                unselectedLabelColor: InterceptlyTheme.textMuted,
                indicatorColor: InterceptlyTheme.indigo500,
                tabs: const [
                  Tab(text: 'Params'),
                  Tab(text: 'Headers'),
                  Tab(text: 'Body'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildEditorField(
                    controller: _queryController,
                    label: 'Query Params (key=value per line)',
                    minLines: 10,
                    maxLines: 16,
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'raw (JSON object)',
                            style: TextStyle(
                              color: InterceptlyTheme.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _formatHeadersJson,
                            icon: const Icon(Icons.auto_fix_high, size: 14),
                            label: const Text('Format JSON'),
                          ),
                        ],
                      ),
                      Expanded(
                        child: TextField(
                          controller: _headersController,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          decoration: const InputDecoration(
                            hintText: '{\n  "Authorization": "Bearer ..."\n}',
                            alignLabelWithHint: true,
                          ),
                          style: const TextStyle(
                            color: InterceptlyTheme.textPrimary,
                            fontFamily: InterceptlyTheme.fontFamily,
                            package: InterceptlyTheme.fontPackage,
                          ),
                        ),
                      ),
                      if (headersJsonError != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Invalid Headers JSON: $headersJsonError',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: InterceptlyTheme.yellow400,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'raw (JSON)',
                            style: TextStyle(
                              color: InterceptlyTheme.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _formatJsonBody,
                            icon: const Icon(Icons.auto_fix_high, size: 14),
                            label: const Text('Format JSON'),
                          ),
                        ],
                      ),
                      Expanded(
                        child: TextField(
                          controller: _bodyController,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          decoration: const InputDecoration(
                            hintText: '{\n  "key": "value"\n}',
                            alignLabelWithHint: true,
                          ),
                          style: const TextStyle(
                            color: InterceptlyTheme.textPrimary,
                            fontFamily: InterceptlyTheme.fontFamily,
                            package: InterceptlyTheme.fontPackage,
                          ),
                        ),
                      ),
                      if (jsonError != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Invalid JSON: $jsonError',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: InterceptlyTheme.yellow400,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (headersJsonError != null) {
                        ToastNotification.show(
                          context,
                          'Headers JSON is invalid',
                        );
                        return;
                      }
                      Navigator.pop(
                        context,
                        _ReplayDraft(
                          method: _methodController.text.trim().toUpperCase(),
                          url: fullUrl,
                          headers: headersMap,
                          body: _bodyController.text,
                        ),
                      );
                    },
                    icon: const Icon(Icons.send, size: 16),
                    label: const Text('Send'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorField({
    required TextEditingController controller,
    required String label,
    required int minLines,
    required int maxLines,
  }) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: InterceptlyTheme.textMuted),
      ),
      style: const TextStyle(
        color: InterceptlyTheme.textPrimary,
        fontFamily: InterceptlyTheme.fontFamily,
        package: InterceptlyTheme.fontPackage,
      ),
    );
  }
}

class _ReplayDraft {
  const _ReplayDraft({
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

  static const Color _keyColor = Color(0xFF7CC5FF);
  static const Color _stringColor = Color(0xFFF78C6C);
  static const Color _numberColor = Color(0xFFC3E88D);
  static const Color _boolNullColor = Color(0xFFFFCB6B);
  static const Color _punctuationColor = Color(0xFF89DDFF);

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
        const TextStyle(
          color: InterceptlyTheme.textPrimary,
          fontFamily: InterceptlyTheme.fontFamily,
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
