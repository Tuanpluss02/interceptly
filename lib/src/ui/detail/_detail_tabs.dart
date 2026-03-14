import 'package:flutter/material.dart';
import 'package:netspecter/src/ui/netspecter_theme.dart';
import 'package:netspecter/src/ui/widgets/json_viewer.dart';

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
    final mStyle = NetSpecterTheme.getMethodStyle(record.method);

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
            fontFamily: NetSpecterTheme.fontFamily,
            package: NetSpecterTheme.fontPackage,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),
        _buildOverviewRow(
          'Status',
          '${record.statusCode}',
          DetailSection.overviewStatus,
        ),
        const SizedBox(height: 16),
        _buildOverviewRow(
          'Duration',
          '${record.durationMs} ms',
          DetailSection.overviewDuration,
        ),
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
              color: NetSpecterTheme.yellow400,
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
        _buildSectionHeader('Request Body', color: NetSpecterTheme.indigo400),
        _buildJsonBox(
          tryParseJson(record.requestBodyPreview),
          DetailSection.requestBody,
        ),
      ],
    );
  }

  Widget buildResponseTab() {
    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
      children: [
        _buildSectionHeader('Response Headers'),
        _buildJsonBox(
          record.responseHeaders,
          DetailSection.responseHeaders,
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('Response Body', color: NetSpecterTheme.green400),
        _buildJsonBox(
          tryParseJson(record.responseBodyPreview),
          DetailSection.responseBody,
        ),
      ],
    );
  }

  Widget buildErrorTab() {
    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
      children: [
        _buildSectionHeader('Error Type', color: NetSpecterTheme.yellow400),
        _buildJsonBox(
          record.errorType ?? 'None',
          DetailSection.errorType,
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('Error Message', color: NetSpecterTheme.yellow400),
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
              style: TextStyle(color: NetSpecterTheme.textMuted)));
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
                    color: NetSpecterTheme.purple400,
                    letterSpacing: 1.0,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: NetSpecterTheme.green500.withValues(alpha: 0.1),
                    border: Border.all(
                        color: NetSpecterTheme.green500.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: const Text(
                    'Live',
                    style: TextStyle(
                      fontFamily: NetSpecterTheme.fontFamily,
                      package: NetSpecterTheme.fontPackage,
                      fontSize: 10,
                      color: NetSpecterTheme.green400,
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
            isOut ? NetSpecterTheme.green400 : NetSpecterTheme.blue400;
        final icon = isOut ? Icons.call_made : Icons.call_received;
        final bgColor = isOut
            ? NetSpecterTheme.green500.withValues(alpha: 0.1)
            : NetSpecterTheme.blue500.withValues(alpha: 0.1);
        final label = isOut ? 'SENT' : 'RECV';

        return Container(
          margin: const EdgeInsets.only(bottom: 12.0),
          decoration: BoxDecoration(
            color: NetSpecterTheme.surfaceContainer,
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
                        fontFamily: NetSpecterTheme.fontFamily,
                        package: NetSpecterTheme.fontPackage,
                        fontSize: 10,
                        color: NetSpecterTheme.textMuted,
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
              color: NetSpecterTheme.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: (valueStyle ??
                    const TextStyle(
                      fontFamily: NetSpecterTheme.fontFamily,
                      package: NetSpecterTheme.fontPackage,
                      fontSize: 12,
                      color: NetSpecterTheme.textSecondary,
                    ))
                .copyWith(
              backgroundColor: highlight ? const Color(0x40FFF59D) : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color ?? NetSpecterTheme.textMuted,
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
        color: NetSpecterTheme.surfaceContainer,
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
