import 'dart:convert';
import 'dart:typed_data';

import 'dart:io';

import 'package:flutter/material.dart';

import '../../model/raw_capture.dart';
import '../../model/body_truncation.dart';
import '../../model/request_record.dart';
import '../../session/body_decode_service.dart';
import '../../session/inspector_session.dart';
import '../interceptly_theme.dart';
import '../widgets/toast_notification.dart';
import 'custom_request_page.dart';

class ReplayHandler {
  const ReplayHandler({
    required this.context,
    required this.session,
    @visibleForTesting this.clientFactory,
  });

  final BuildContext context;
  final InspectorSession session;
  @visibleForTesting
  final HttpClient Function()? clientFactory;

  void showReplayMenu(RequestRecord record) {
    showModalBottomSheet(
      context: context,
      backgroundColor: InterceptlyTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => Theme(
        data: InterceptlyTheme.themeData(context: context),
        child: Container(
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
                leading: const Icon(
                  Icons.refresh,
                  color: InterceptlyTheme.indigo500,
                ),
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
                leading: const Icon(
                  Icons.edit_note,
                  color: InterceptlyTheme.indigo500,
                ),
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
      bodyBytes: record.requestBodyBytes,
      truncation: record.requestTruncation,
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

    String initialBodyText = '';
    if (record.requestBodyBytes != null &&
        record.requestBodyBytes!.isNotEmpty) {
      try {
        initialBodyText = utf8.decode(record.requestBodyBytes!);
      } catch (_) {
        final rawBody = record.requestBodyPreview;
        initialBodyText =
            (rawBody != null && !_isPlaceholder(rawBody)) ? rawBody : '';
      }
    } else {
      final rawBody = record.requestBodyPreview;
      initialBodyText =
          (rawBody != null && !_isPlaceholder(rawBody)) ? rawBody : '';
    }

    final result = await Navigator.of(context).push<CustomRequestDraft>(
      MaterialPageRoute(
        builder: (context) => CustomRequestPage(
          initialMethod: record.method.toUpperCase(),
          initialBaseUrl: baseUrl,
          initialQueryText: _queryParamsToText(queryParams),
          initialHeadersText: _headersToText(record.requestHeaders),
          initialBodyText: initialBodyText,
        ),
      ),
    );

    if (result == null) return;

    await _sendRequest(
      method: result.method,
      url: result.url,
      headers: result.headers,
      body: result.body,
      bodyBytes: utf8.encode(result.body),
      truncation: BodyTruncation.complete(utf8.encode(result.body).length),
    );
  }

  Future<void> _sendRequest({
    required String method,
    required String url,
    required Map<String, String> headers,
    required String? body,
    Uint8List? bodyBytes,
    required BodyTruncation truncation,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      ToastNotification.show('Invalid URL', contextHint: context);
      return;
    }

    if (_isUnsupportedMethod(method)) {
      ToastNotification.show(
        'Unsupported method: $method',
        contextHint: context,
      );
      return;
    }

    final cleanedHeaders = _sanitizeReplayHeaders(headers);
    final isPlaceholder = _isPlaceholder(body);

    if (bodyBytes == null &&
        truncation.isPreviewOnly &&
        body != null &&
        body.isNotEmpty &&
        !isPlaceholder) {
      ToastNotification.show(
        'Replaying the preview only — the stored body is complete but too '
        'large to send here.',
        contextHint: context,
      );
    }

    final upperMethod = method.toUpperCase();
    final allowBody =
        upperMethod != 'GET' && upperMethod != 'HEAD' && upperMethod != 'TRACE';

    Uint8List? bodyBytesToSend;
    if (allowBody) {
      if (bodyBytes != null && bodyBytes.isNotEmpty) {
        bodyBytesToSend = bodyBytes;
      } else if (body != null && body.isNotEmpty && !isPlaceholder) {
        bodyBytesToSend = Uint8List.fromList(utf8.encode(body));
      }
    }

    final headersToSend = Map<String, String>.from(cleanedHeaders);
    if (allowBody && bodyBytesToSend != null && bodyBytesToSend.isNotEmpty) {
      headersToSend.putIfAbsent(
        'content-type',
        () => 'application/json; charset=utf-8',
      );
    }

    final client = clientFactory?.call() ?? HttpClient();
    final stopwatch = Stopwatch()..start();
    final start = DateTime.now();

    try {
      ToastNotification.show('Sending request...', contextHint: context);
      final request = await client.openUrl(upperMethod, uri);
      headersToSend.forEach((key, value) {
        request.headers.set(key, value);
      });
      if (allowBody && bodyBytesToSend != null && bodyBytesToSend.isNotEmpty) {
        request.add(bodyBytesToSend);
      }

      final response = await request.close();
      final responseBody = await response.fold<List<int>>(
        <int>[],
        (previous, element) => previous..addAll(element),
      );
      stopwatch.stop();

      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });

      session.record(
        RawCapture(
          id: 'r_replay_${DateTime.now().microsecondsSinceEpoch}',
          method: upperMethod,
          url: url,
          requestHeaders: headersToSend,
          responseHeaders: responseHeaders,
          statusCode: response.statusCode,
          durationMs: stopwatch.elapsedMilliseconds,
          timestamp: start,
          requestBodyBytes: bodyBytesToSend != null
              ? RawCapture.wrapBytes(bodyBytesToSend)
              : null,
          responseBodyBytes:
              RawCapture.wrapBytes(Uint8List.fromList(responseBody)),
          responseContentType: response.headers.contentType?.mimeType,
        ),
      );

      if (!context.mounted) return;
      ToastNotification.show(
        'Replay sent (${response.statusCode})',
        contextHint: context,
      );
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

  bool _isPlaceholder(String? body) {
    if (body == null) return false;
    return BodyDecodeService.isPlaceholder(body) ||
        body.startsWith('\x00') ||
        body.startsWith('[binary:');
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
