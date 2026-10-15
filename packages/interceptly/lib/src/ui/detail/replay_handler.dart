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

/// Handles replaying requests and opening custom request edit views.
class ReplayHandler {
  const ReplayHandler({
    required this.context,
    required this.session,
    @visibleForTesting this.clientFactory,
    @visibleForTesting this.confirmDialog,
  });

  final BuildContext context;
  final InspectorSession session;

  @visibleForTesting
  final HttpClient Function()? clientFactory;

  @visibleForTesting
  final Future<bool> Function(BuildContext context, String method)?
      confirmDialog;

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
                  retry(record, confirm: true);
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

  /// Retries sending [record] with same headers, URL, and payload.
  ///
  /// Prompts for confirmation before replaying any method when a
  /// confirmation UI is available.
  Future<void> retry(RequestRecord record, {bool? confirm}) async {
    if (_isUnsupportedMethod(record.method)) {
      ToastNotification.show(
        'Retry is not supported for ${record.method}',
        contextHint: context,
      );
      return;
    }

    final shouldPrompt =
        confirm ?? (confirmDialog != null || clientFactory == null);
    if (shouldPrompt) {
      final confirmed = await _confirmNonIdempotent(record.method);
      if (!confirmed) return;
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

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      ToastNotification.show(
        'Replay blocked: scheme "$scheme" is not allowed',
        contextHint: context,
      );
      return;
    }

    if (_isBlockedHost(uri.host)) {
      ToastNotification.show(
        'Replay blocked: unsafe target address (${uri.host})',
        contextHint: context,
      );
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

    if (truncation.hasDataLoss) {
      ToastNotification.show(
        'Warning: Request body was truncated during capture and may be incomplete.',
        contextHint: context,
      );
    }

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
    try {
      client.connectionTimeout = const Duration(seconds: 15);
    } catch (_) {}

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

  Future<bool> _confirmNonIdempotent(String method) async {
    if (confirmDialog != null) {
      return confirmDialog!(context, method);
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Replay'),
        content: Text(
          'Replaying a $method request may modify server state or perform non-idempotent actions. Proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Replay'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @visibleForTesting
  static bool isBlockedHost(String host) {
    var clean =
        host.toLowerCase().trim().replaceAll('[', '').replaceAll(']', '');
    while (clean.endsWith('.')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (clean.isEmpty) return true;
    if (clean == 'localhost') return true;
    if (clean == '127.0.0.1' || clean.startsWith('127.')) return true;
    if (clean == '::1' || clean == '0:0:0:0:0:0:0:1') return true;
    if (clean == '0.0.0.0') return true;
    if (clean.startsWith('169.254.')) return true;
    if (clean.startsWith('fe80:')) return true;
    if (clean.startsWith('10.') || clean == '10') return true;
    if (clean.startsWith('192.168.')) return true;
    if (_isPrivate172(clean)) return true;
    if (clean == 'internal' ||
        clean == 'local' ||
        clean.endsWith('.internal') ||
        clean.endsWith('.local')) {
      return true;
    }
    return false;
  }

  static bool _isPrivate172(String host) {
    if (!host.startsWith('172.')) return false;
    final rest = host.substring(4);
    final dot = rest.indexOf('.');
    if (dot <= 0) return false;
    final second = int.tryParse(rest.substring(0, dot));
    if (second == null) return false;
    return second >= 16 && second <= 31;
  }

  bool _isBlockedHost(String host) {
    return isBlockedHost(host);
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
