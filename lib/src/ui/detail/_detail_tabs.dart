import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/utils/error_summary.dart';
import 'package:interceptly/src/ui/widgets/json_viewer.dart';

import '../../model/request_record.dart';
import '_detail_search.dart';

class DetailTabsBuilder {
  final RequestRecord record;
  final List<DetailMatch> matches;
  final int? activeGlobalIndex;
  final String query;
  final bool urlDecodeEnabled;
  final dynamic Function(String?) tryParseJson;

  DetailTabsBuilder({
    required this.record,
    required this.matches,
    required this.activeGlobalIndex,
    required this.query,
    required this.urlDecodeEnabled,
    required this.tryParseJson,
  });

  Widget buildOverviewTab() {
    final mStyle = InterceptlyTheme.getMethodStyle(record.method);
    final isPending = record.statusCode == 0 && !record.hasError;
    final isErrorWithoutStatus = record.statusCode == 0 && record.hasError;
    final shortError = summarizeRequestError(
      errorType: record.errorType,
      errorMessage: record.errorMessage,
    );

    String displayUrl = record.url;
    if (urlDecodeEnabled) {
      try {
        displayUrl = Uri.decodeFull(record.url);
      } catch (_) {}
    }

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildOverviewRow('URL', displayUrl, DetailSection.overviewUrl),
        const SizedBox(height: 16),
        _buildOverviewRow(
          'Method',
          record.method,
          DetailSection.overviewMethod,
          valueStyle: TextStyle(
            color: mStyle.text,
            fontFamily: InterceptlyTheme.fontFamily,
            package: InterceptlyTheme.fontPackage,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),
        _buildOverviewRow(
          'Status',
          isPending
              ? 'Loading'
              : isErrorWithoutStatus
                  ? 'Error'
                  : '${record.statusCode}',
          DetailSection.overviewStatus,
        ),
        const SizedBox(height: 16),
        _buildOverviewRow(
          'Duration',
          isPending ? 'loading…' : '${record.durationMs} ms',
          DetailSection.overviewDuration,
        ),
        if (record.hasError) ...[
          const SizedBox(height: 16),
          _buildOverviewRow(
            'Error',
            shortError,
            DetailSection.errorType,
            valueStyle: const TextStyle(
              color: InterceptlyTheme.yellow400,
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildOverviewRow(
          'Time',
          record.timestamp.toIso8601String(),
          DetailSection.overviewTime,
        ),
        if (record.isBodyTruncated) ...[
          const SizedBox(height: 16),
          _buildOverviewRow(
            'Note',
            'Body truncated — response exceeded the size limit.',
            DetailSection.overviewNote,
            valueStyle: const TextStyle(
              color: InterceptlyTheme.yellow400,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget buildRequestTab() {
    var urlForParsing = record.url;
    if (urlDecodeEnabled) {
      try {
        urlForParsing = Uri.decodeFull(record.url);
      } catch (_) {}
    }

    final uri = Uri.tryParse(urlForParsing);
    final hasQueryParams = uri != null && uri.queryParameters.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
      children: [
        _buildSectionHeader('Request Headers'),
        _buildJsonBox(
          record.requestHeaders,
          DetailSection.requestHeaders,
        ),
        const SizedBox(height: 24),
        if (hasQueryParams) ...[
          _buildSectionHeader('Query Parameters'),
          _buildJsonBox(
            uri.queryParameters,
            DetailSection.queryParams,
          ),
          const SizedBox(height: 24),
        ],
        _buildSectionHeader('Request Body', color: InterceptlyTheme.indigo400),
        _buildBodyPreviewSection(
          contentType: record.requestContentType,
          headers: record.requestHeaders,
          bodyPreview: record.requestBodyPreview,
          bodyBytes: record.requestBodyBytesPreview,
          section: DetailSection.requestBody,
        ),
      ],
    );
  }

  Widget buildResponseTab() {
    final isPending = record.statusCode == 0 && !record.hasError;
    final isErrorWithoutResponse = record.statusCode == 0 && record.hasError;
    final shortError = summarizeRequestError(
      errorType: record.errorType,
      errorMessage: record.errorMessage,
    );

    if (isPending) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: InterceptlyTheme.indigo500),
            SizedBox(height: 12),
            Text(
              'Waiting for response...',
              style: TextStyle(color: InterceptlyTheme.textMuted),
            ),
          ],
        ),
      );
    }

    if (isErrorWithoutResponse) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              shortError,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: InterceptlyTheme.yellow400,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              record.errorMessage ??
                  'Request failed before receiving a response.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: InterceptlyTheme.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
      children: [
        _buildSectionHeader('Response Headers'),
        _buildJsonBox(
          record.responseHeaders,
          DetailSection.responseHeaders,
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('Response Body', color: InterceptlyTheme.green400),
        _buildBodyPreviewSection(
          contentType: record.responseContentType,
          headers: record.responseHeaders,
          bodyPreview: record.responseBodyPreview,
          bodyBytes: record.responseBodyBytesPreview,
          section: DetailSection.responseBody,
        ),
      ],
    );
  }

  Widget buildErrorTab() {
    final shortError = summarizeRequestError(
      errorType: record.errorType,
      errorMessage: record.errorMessage,
    );

    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
      children: [
        _buildSectionHeader('Error Summary', color: InterceptlyTheme.yellow400),
        _buildJsonBox(
          shortError,
          DetailSection.errorType,
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('Error Type', color: InterceptlyTheme.yellow400),
        _buildJsonBox(
          record.errorType ?? 'None',
          DetailSection.errorType,
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('Error Message', color: InterceptlyTheme.yellow400),
        _buildJsonBox(
          record.errorMessage ?? 'None',
          DetailSection.errorMessage,
        ),
      ],
    );
  }

  Widget buildMessagesTab() {
    // Note: If WebSockets messages are not captured by RequestRecord, this will simply say no messages
    final messages = <Map<String, dynamic>>[];

    if (messages.isEmpty) {
      return const Center(
          child: Text('No WebSocket messages captured.',
              style: TextStyle(color: InterceptlyTheme.textMuted)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: messages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CONNECTION FRAMES',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: InterceptlyTheme.purple400,
                    letterSpacing: 1.0,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: InterceptlyTheme.green500.withValues(alpha: 0.1),
                    border: Border.all(
                        color:
                            InterceptlyTheme.green500.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: const Text(
                    'Live',
                    style: TextStyle(
                      fontFamily: InterceptlyTheme.fontFamily,
                      package: InterceptlyTheme.fontPackage,
                      fontSize: 10,
                      color: InterceptlyTheme.green400,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final msg = messages[index - 1];
        final isOut = msg['type'] == 'out';
        final iconColor =
            isOut ? InterceptlyTheme.green400 : InterceptlyTheme.blue400;
        final icon = isOut ? Icons.call_made : Icons.call_received;
        final bgColor = isOut
            ? InterceptlyTheme.green500.withValues(alpha: 0.1)
            : InterceptlyTheme.blue500.withValues(alpha: 0.1);
        final label = isOut ? 'SENT' : 'RECV';

        return Container(
          margin: const EdgeInsets.only(bottom: 12.0),
          decoration: BoxDecoration(
            color: InterceptlyTheme.surfaceContainer,
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: bgColor,
                  border: Border(
                    bottom:
                        BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: iconColor, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: iconColor,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      msg['time'] ?? '',
                      style: const TextStyle(
                        fontFamily: InterceptlyTheme.fontFamily,
                        package: InterceptlyTheme.fontPackage,
                        fontSize: 10,
                        color: InterceptlyTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: JsonViewer(
                  data: msg['data'],
                  searchQuery: query.isEmpty ? null : query,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverviewRow(
    String label,
    String value,
    DetailSection section, {
    TextStyle? valueStyle,
  }) {
    int matchOffset = matches.indexWhere((m) => m.section == section);
    if (matchOffset < 0) matchOffset = 0;
    final sectionMatchCount = matches.where((m) => m.section == section).length;

    final highlight = activeGlobalIndex != null &&
        activeGlobalIndex! >= matchOffset &&
        activeGlobalIndex! < matchOffset + sectionMatchCount;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: InterceptlyTheme.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: (valueStyle ??
                    const TextStyle(
                      fontFamily: InterceptlyTheme.fontFamily,
                      package: InterceptlyTheme.fontPackage,
                      fontSize: 12,
                      color: InterceptlyTheme.textSecondary,
                    ))
                .copyWith(
              backgroundColor: highlight ? const Color(0x40FFF59D) : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBodyPreviewSection({
    required String? contentType,
    required Map<String, String> headers,
    required String? bodyPreview,
    required Uint8List? bodyBytes,
    required DetailSection section,
  }) {
    final encodingLabel = _buildEncodingLabel(headers, bodyBytes);
    final isBinary = _isBinaryPayload(contentType, bodyPreview);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBodyMetaChips(
          contentType: contentType,
          encodingLabel: encodingLabel,
        ),
        if (contentType != null || encodingLabel != null)
          const SizedBox(height: 8),
        isBinary
            ? _buildBinaryPreview(
                contentType: contentType,
                bodyPreview: bodyPreview,
                bodyBytes: bodyBytes,
                section: section,
              )
            : _buildJsonBox(
                _formatBodyData(
                  contentType: contentType,
                  bodyPreview: bodyPreview,
                ),
                section,
              ),
      ],
    );
  }

  Widget _buildBodyMetaChips({
    required String? contentType,
    required String? encodingLabel,
  }) {
    if ((contentType == null || contentType.isEmpty) && encodingLabel == null) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (contentType != null && contentType.isNotEmpty)
          _buildMetaChip('content-type: $contentType'),
        if (encodingLabel != null) _buildMetaChip(encodingLabel),
      ],
    );
  }

  Widget _buildMetaChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: InterceptlyTheme.surfaceContainer,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: InterceptlyTheme.fontFamily,
          package: InterceptlyTheme.fontPackage,
          fontSize: 11,
          color: InterceptlyTheme.textMuted,
        ),
      ),
    );
  }

  dynamic _formatBodyData({
    required String? contentType,
    required String? bodyPreview,
  }) {
    if (bodyPreview == null || bodyPreview.isEmpty) return 'No Data';
    final ct = (contentType ?? '').toLowerCase();

    if (ct.contains('application/x-www-form-urlencoded')) {
      return _parseFormUrlEncoded(bodyPreview);
    }

    if (ct.contains('multipart/form-data')) {
      return _parseMultipartSummary(bodyPreview);
    }

    if (ct.contains('application/graphql')) {
      return {
        'query': bodyPreview,
      };
    }

    final parsed = tryParseJson(bodyPreview);
    if (parsed is Map<String, dynamic> &&
        (parsed.containsKey('query') ||
            parsed.containsKey('operationName') ||
            parsed.containsKey('variables'))) {
      return {
        'operationName': parsed['operationName'],
        'query': parsed['query'],
        'variables': parsed['variables'],
      };
    }

    return parsed;
  }

  Map<String, dynamic> _parseFormUrlEncoded(String body) {
    try {
      return Uri.splitQueryString(body, encoding: utf8);
    } catch (_) {
      final map = <String, String>{};
      for (final part in body.split('&')) {
        if (part.isEmpty) continue;
        final idx = part.indexOf('=');
        if (idx < 0) {
          map[Uri.decodeQueryComponent(part)] = '';
        } else {
          final k = part.substring(0, idx);
          final v = part.substring(idx + 1);
          map[Uri.decodeQueryComponent(k)] = Uri.decodeQueryComponent(v);
        }
      }
      return map;
    }
  }

  Map<String, dynamic> _parseMultipartSummary(String body) {
    final fields = <String, String>{};
    final files = <Map<String, String>>[];
    final rawLines = <String>[];

    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('[field] ')) {
        final payload = trimmed.substring(8);
        final idx = payload.indexOf('=');
        if (idx > 0) {
          fields[payload.substring(0, idx).trim()] =
              payload.substring(idx + 1).trim();
        } else {
          rawLines.add(trimmed);
        }
        continue;
      }

      if (trimmed.startsWith('[file] ')) {
        final payload = trimmed.substring(7);
        final idx = payload.indexOf(':');
        if (idx > 0) {
          final field = payload.substring(0, idx).trim();
          final rest = payload.substring(idx + 1).trim();
          files.add({'field': field, 'value': rest});
        } else {
          files.add({'value': payload});
        }
        continue;
      }

      rawLines.add(trimmed);
    }

    return {
      'fields': fields,
      'files': files,
      if (rawLines.isNotEmpty) 'raw': rawLines,
    };
  }

  bool _isBinaryPayload(String? contentType, String? bodyPreview) {
    final ct = (contentType ?? '').toLowerCase();
    if (ct.startsWith('image/') ||
        ct.startsWith('audio/') ||
        ct.startsWith('video/') ||
        ct.contains('application/pdf') ||
        ct.contains('application/octet-stream') ||
        ct.contains('protobuf') ||
        ct.contains('msgpack')) {
      return true;
    }

    return bodyPreview != null && bodyPreview.startsWith('[binary:');
  }

  Widget _buildBinaryPreview({
    required String? contentType,
    required String? bodyPreview,
    required Uint8List? bodyBytes,
    required DetailSection section,
  }) {
    final kind = _binaryKind(contentType);
    final meta = <String, dynamic>{
      'kind': kind,
      'contentType': contentType ?? 'unknown',
      'sizeBytes': bodyBytes?.length ?? _extractBinarySize(bodyPreview),
    };

    if (kind == 'pdf' && bodyBytes != null && bodyBytes.isNotEmpty) {
      final head = utf8.decode(
        bodyBytes.sublist(0, bodyBytes.length < 12 ? bodyBytes.length : 12),
        allowMalformed: true,
      );
      meta['pdfHeader'] = head;
    }

    if ((kind == 'protobuf' || kind == 'msgpack' || kind == 'binary') &&
        bodyBytes != null &&
        bodyBytes.isNotEmpty) {
      meta['hexPreview'] = _hexPreview(bodyBytes, 48);
      meta['note'] = kind == 'protobuf'
          ? 'Protobuf preview is raw bytes (schema required for decode).'
          : kind == 'msgpack'
              ? 'MessagePack preview is raw bytes (schema-aware decode not available).'
              : 'Binary preview shown as metadata + hex sample.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildJsonBox(meta, section),
        if (kind == 'image' && bodyBytes != null && bodyBytes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: InterceptlyTheme.surfaceContainer,
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              borderRadius: BorderRadius.circular(12.0),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.memory(
              bodyBytes,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text(
                    'Unable to render thumbnail from current preview bytes.',
                    style: TextStyle(color: InterceptlyTheme.textMuted),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  String _binaryKind(String? contentType) {
    final ct = (contentType ?? '').toLowerCase();
    if (ct.startsWith('image/')) return 'image';
    if (ct.contains('application/pdf')) return 'pdf';
    if (ct.contains('protobuf')) return 'protobuf';
    if (ct.contains('msgpack')) return 'msgpack';
    return 'binary';
  }

  int? _extractBinarySize(String? preview) {
    if (preview == null) return null;
    final m = RegExp(r'\[binary:\s*(\d+)\s*bytes\]').firstMatch(preview);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  String _hexPreview(Uint8List bytes, int maxBytes) {
    final take = bytes.length < maxBytes ? bytes.length : maxBytes;
    final sb = StringBuffer();
    for (var i = 0; i < take; i++) {
      sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
      if (i != take - 1) sb.write(' ');
    }
    if (bytes.length > maxBytes) {
      sb.write(' …');
    }
    return sb.toString();
  }

  String? _buildEncodingLabel(Map<String, String> headers, Uint8List? bytes) {
    final encoding = _headerValue(headers, 'content-encoding');
    if (encoding == null || encoding.trim().isEmpty) return null;
    final state = _inferEncodingState(encoding, bytes);
    return 'content-encoding: $encoding ($state)';
  }

  String? _headerValue(Map<String, String> headers, String key) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == key.toLowerCase()) return entry.value;
    }
    return null;
  }

  String _inferEncodingState(String encoding, Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return 'unknown';
    final lower = encoding.toLowerCase();

    if (lower.contains('gzip')) {
      final hasMagic =
          bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
      return hasMagic ? 'not decoded' : 'decoded';
    }

    if (lower.contains('br')) {
      return _looksMostlyText(bytes) ? 'decoded' : 'not decoded';
    }

    if (lower.contains('deflate')) {
      return _looksMostlyText(bytes) ? 'decoded' : 'unknown';
    }

    return _looksMostlyText(bytes) ? 'decoded' : 'unknown';
  }

  bool _looksMostlyText(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    final sampleLen = bytes.length < 256 ? bytes.length : 256;
    var printable = 0;
    for (var i = 0; i < sampleLen; i++) {
      final b = bytes[i];
      final isPrintableAscii = b >= 0x20 && b <= 0x7E;
      final isWhitespace = b == 0x09 || b == 0x0A || b == 0x0D;
      if (isPrintableAscii || isWhitespace) printable++;
    }
    return printable / sampleLen >= 0.85;
  }

  Widget _buildSectionHeader(String title, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color ?? InterceptlyTheme.textMuted,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildJsonBox(
    dynamic data,
    DetailSection section,
  ) {
    int matchOffset = matches.indexWhere((m) => m.section == section);
    if (matchOffset < 0) matchOffset = 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: InterceptlyTheme.surfaceContainer,
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: JsonViewer(
        data: data,
        searchQuery: query.isEmpty ? null : query,
        matchOffset: matchOffset,
        activeGlobalIndex: activeGlobalIndex,
      ),
    );
  }
}
