import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../capture/http/interceptly_http_client.dart';
import '../../model/request_record.dart';
import '../../session/inspector_session.dart';
import '../interceptly_theme.dart';
import '../widgets/toast_notification.dart';
import 'custom_request_page.dart';

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
                color: InterceptlyTheme.controlMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading:
                  const Icon(Icons.refresh, color: InterceptlyTheme.indigo500),
              title: Text(
                'Retry Request',
                style: InterceptlyTheme.typography.bodyMediumMedium.copyWith(
                  color: InterceptlyTheme.textPrimary,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                retry(record);
              },
            ),
            Divider(color: InterceptlyTheme.dividerSubtle, height: 1),
            ListTile(
              leading: const Icon(Icons.edit_note,
                  color: InterceptlyTheme.indigo500),
              title: Text(
                'Duplicate & Edit',
                style: InterceptlyTheme.typography.bodyMediumMedium.copyWith(
                  color: InterceptlyTheme.textPrimary,
                ),
              ),
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
        'Retry is not supported for ${record.method}',
        contextHint: context,
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
        'Edit/Replay is not supported for ${record.method}',
        contextHint: context,
      );
      return;
    }

    final (baseUrl, queryParams) = _splitUrlForEditing(record.url);

    final result = await Navigator.of(context).push<CustomRequestDraft>(
      MaterialPageRoute(
        builder: (context) => CustomRequestPage(
          initialMethod: record.method.toUpperCase(),
          initialBaseUrl: baseUrl,
          initialQueryText: _queryParamsToText(queryParams),
          initialHeadersText: _headersToText(record.requestHeaders),
          initialBodyText: record.requestBodyPreview ?? '',
          session: session,
        ),
      ),
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
      ToastNotification.show('Invalid URL', contextHint: context);
      return;
    }

    if (_isUnsupportedMethod(method)) {
      ToastNotification.show('Unsupported method: $method',
          contextHint: context);
      return;
    }

    final cleanedHeaders = _sanitizeReplayHeaders(headers);

    if (isBodyTruncated && body != null && body.isNotEmpty) {
      ToastNotification.show('Warning: body may be truncated',
          contextHint: context);
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
      ToastNotification.show('Sending request...', contextHint: context);
      final streamed = await client.send(request);
      await streamed.stream.drain<void>();
      if (!context.mounted) return;
      ToastNotification.show('Replay sent (${streamed.statusCode})',
          contextHint: context);
    } catch (e) {
      if (!context.mounted) return;
      ToastNotification.show('Replay failed: $e', contextHint: context);
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
