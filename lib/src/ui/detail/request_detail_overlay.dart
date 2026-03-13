import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:netspecter/src/ui/netspecter_theme.dart';
import 'package:netspecter/src/ui/widgets/json_viewer.dart';
import 'package:netspecter/src/ui/widgets/toast_notification.dart';

import '../../model/index_entry.dart';
import '../../model/request_record.dart';
import '../../storage/inspector_session.dart';

class RequestDetailOverlay extends StatefulWidget {
  final IndexEntry entry;
  final InspectorSession session;

  const RequestDetailOverlay({
    super.key, 
    required this.entry,
    required this.session,
  });

  @override
  State<RequestDetailOverlay> createState() => _RequestDetailOverlayState();
}

class _RequestDetailOverlayState extends State<RequestDetailOverlay>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  late Future<RequestRecord> _recordFuture;

  String _query = '';
  int _currentMatchIndex = 0;

  @override
  void initState() {
    super.initState();
    _recordFuture = widget.session.loadDetail(widget.entry);
    final isWs = widget.entry.method == 'WS';
    _tabController = TabController(length: isWs ? 2 : 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _copyAsCurl() {
    // TODO: Generate cURL command
    Clipboard.setData(const ClipboardData(text: 'curl ...'));
    ToastNotification.show(context, 'Copied as cURL!');
  }

  dynamic _tryParseJson(String? content) {
    if (content == null || content.isEmpty) return content;
    try {
      return jsonDecode(content);
    } catch (_) {
      return content;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final isWs = entry.method == 'WS';
    final sStyle = NetSpecterTheme.getStatusStyle(entry.statusCode);
    final path = Uri.tryParse(entry.url)?.path ?? entry.url;

    return Scaffold(
      backgroundColor: NetSpecterTheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          path,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16.0),
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: sStyle.bg,
              borderRadius: BorderRadius.circular(4.0),
            ),
            alignment: Alignment.center,
            child: Text(
              '${entry.statusCode} ${entry.statusCode == 200 ? 'OK' : ''}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: sStyle.text,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48.0),
          child: Column(
            children: [
              Container(height: 1, color: Colors.white.withValues(alpha: 0.05)),
              TabBar(
                controller: _tabController,
                indicatorColor: NetSpecterTheme.indigo500,
                labelColor: NetSpecterTheme.indigo400,
                unselectedLabelColor: NetSpecterTheme.textQuaternary,
                isScrollable: true,
                tabs: isWs
                    ? const [
                        Tab(text: 'Overview'),
                        Tab(text: 'Messages'),
                      ]
                    : const [
                        Tab(text: 'Overview'),
                        Tab(text: 'Request'),
                        Tab(text: 'Response'),
                        Tab(text: 'Error'),
                      ],
              ),
            ],
          ),
        ),
      ),
      body: FutureBuilder<RequestRecord>(
        future: _recordFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: NetSpecterTheme.indigo500),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          final record = snapshot.data!;
          final matches = _computeMatches(record, _query, isWs);
          final totalMatches = matches.length;

          int effectiveIndex = _currentMatchIndex;
          if (totalMatches > 0) {
            effectiveIndex %= totalMatches;
            if (effectiveIndex < 0) {
              effectiveIndex += totalMatches;
            }
          } else {
            effectiveIndex = 0;
          }

          final active =
              totalMatches == 0 ? null : matches[effectiveIndex];

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (active != null &&
                _tabController.index != active.tabIndex &&
                _tabController.length > active.tabIndex) {
              _tabController.animateTo(active.tabIndex);
            }
          });

          return Column(
            children: [
              // Detail Search Bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                decoration: BoxDecoration(
                  color: NetSpecterTheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          setState(() {
                            _query = value.trim();
                            _currentMatchIndex = 0;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search in details...',
                          hintStyle: const TextStyle(
                            color: NetSpecterTheme.textMuted,
                            fontSize: 14,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: NetSpecterTheme.textMuted,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: NetSpecterTheme.surfaceContainer,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10.0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: const BorderSide(
                              color: NetSpecterTheme.indigo500,
                              width: 1.0,
                            ),
                          ),
                        ),
                        style: const TextStyle(
                          color: NetSpecterTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      totalMatches == 0
                          ? '0 / 0'
                          : '${effectiveIndex + 1} / $totalMatches',
                      style: const TextStyle(
                        fontSize: 12,
                        color: NetSpecterTheme.textMuted,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.keyboard_arrow_up,
                        size: 20,
                        color: NetSpecterTheme.textMuted,
                      ),
                      tooltip: 'Previous match',
                      onPressed: totalMatches == 0
                          ? null
                          : () {
                              setState(() {
                                _currentMatchIndex--;
                              });
                            },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: NetSpecterTheme.textMuted,
                      ),
                      tooltip: 'Next match',
                      onPressed: totalMatches == 0
                          ? null
                          : () {
                              setState(() {
                                _currentMatchIndex++;
                              });
                            },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    TabBarView(
                      controller: _tabController,
                      children: isWs
                          ? [
                              _buildOverviewTab(record, active),
                              _buildMessagesTab(record),
                            ]
                          : [
                              _buildOverviewTab(record, active),
                              _buildRequestTab(record, active),
                              _buildResponseTab(record, active),
                              _buildErrorTab(record, active),
                            ],
                    ),
                    // FAB overlay
                    Positioned(
                      bottom: 24,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: ElevatedButton.icon(
                          onPressed: _copyAsCurl,
                          icon: const Icon(Icons.terminal, size: 18),
                          label: const Text('Copy as cURL'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: NetSpecterTheme.indigo500,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                              vertical: 14.0,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30.0),
                            ),
                            elevation: 8,
                            shadowColor: NetSpecterTheme.indigo500
                                .withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOverviewTab(RequestRecord record, _DetailMatch? active) {
    final mStyle = NetSpecterTheme.getMethodStyle(record.method);

    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100), // padding for FAB
      children: [
        _buildOverviewRow('URL', record.url,
            highlight: _isActive(active, 0, _DetailSection.overviewUrl)),
        const SizedBox(height: 16),
        _buildOverviewRow(
          'Method',
          record.method,
          valueStyle: TextStyle(
            color: mStyle.text,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          highlight:
              _isActive(active, 0, _DetailSection.overviewMethod),
        ),
        const SizedBox(height: 16),
        _buildOverviewRow(
          'Status',
          '${record.statusCode}',
          highlight: _isActive(active, 0, _DetailSection.overviewStatus),
        ),
        const SizedBox(height: 16),
        _buildOverviewRow(
          'Duration',
          '${record.durationMs} ms',
          highlight: _isActive(active, 0, _DetailSection.overviewDuration),
        ),
        const SizedBox(height: 16),
        _buildOverviewRow(
          'Time',
          record.timestamp.toIso8601String(),
          highlight: _isActive(active, 0, _DetailSection.overviewTime),
        ),
        if (record.isBodyTruncated) ...[
          const SizedBox(height: 16),
          _buildOverviewRow(
            'Note',
            'Body truncated — response exceeded the size limit.',
            valueStyle: const TextStyle(
              color: NetSpecterTheme.yellow400,
              fontSize: 12,
            ),
            highlight:
                _isActive(active, 0, _DetailSection.overviewNote),
          ),
        ],
      ],
    );
  }

  Widget _buildOverviewRow(
    String label,
    String value, {
    TextStyle? valueStyle,
    bool highlight = false,
  }) {
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
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: NetSpecterTheme.textSecondary,
                    ))
                .copyWith(
              backgroundColor:
                  highlight ? const Color(0x40FFF59D) : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestTab(RequestRecord record, _DetailMatch? active) {
    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
      children: [
        _buildSectionHeader('Request Headers'),
        _buildJsonBox(
          record.requestHeaders,
          highlight:
              _isActive(active, 1, _DetailSection.requestHeaders),
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('Request Body',
            color: NetSpecterTheme.indigo400),
        _buildJsonBox(
          _tryParseJson(record.requestBodyPreview),
          highlight:
              _isActive(active, 1, _DetailSection.requestBody),
        ),
      ],
    );
  }

  Widget _buildResponseTab(RequestRecord record, _DetailMatch? active) {
    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
      children: [
        _buildSectionHeader('Response Headers'),
        _buildJsonBox(
          record.responseHeaders,
          highlight:
              _isActive(active, 2, _DetailSection.responseHeaders),
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('Response Body',
            color: NetSpecterTheme.green400),
        _buildJsonBox(
          _tryParseJson(record.responseBodyPreview),
          highlight:
              _isActive(active, 2, _DetailSection.responseBody),
        ),
      ],
    );
  }

  Widget _buildErrorTab(RequestRecord record, _DetailMatch? active) {
    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
      children: [
        _buildSectionHeader('Error Type',
            color: NetSpecterTheme.yellow400),
        _buildJsonBox(
          record.errorType ?? 'None',
          highlight:
              _isActive(active, 3, _DetailSection.errorType),
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('Error Message',
            color: NetSpecterTheme.yellow400),
        _buildJsonBox(
          record.errorMessage ?? 'None',
          highlight:
              _isActive(active, 3, _DetailSection.errorMessage),
        ),
      ],
    );
  }

  Widget _buildMessagesTab(RequestRecord record) {
    // Note: If WebSockets messages are not captured by RequestRecord, this will simply say no messages
    final messages = [];

    if (messages.isEmpty) {
      return const Center(child: Text('No WebSocket messages captured.', style: TextStyle(color: NetSpecterTheme.textMuted)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: NetSpecterTheme.green500.withValues(alpha: 0.1),
                    border: Border.all(color: NetSpecterTheme.green500.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: const Text(
                    'Live',
                    style: TextStyle(
                      fontFamily: 'monospace',
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
        final iconColor = isOut ? NetSpecterTheme.green400 : NetSpecterTheme.blue400;
        final icon = isOut ? Icons.call_made : Icons.call_received;
        final bgColor = isOut ? NetSpecterTheme.green500.withValues(alpha: 0.1) : NetSpecterTheme.blue500.withValues(alpha: 0.1);
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
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: bgColor,
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
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
                      msg['time'],
                      style: const TextStyle(
                        fontFamily: 'monospace',
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
                  searchQuery: _query.isEmpty ? null : _query,
                ),
              ),
            ],
          ),
        );
      },
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
    dynamic data, {
    bool highlight = false,
  }) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: NetSpecterTheme.surfaceContainer,
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: JsonViewer(
            data: data,
            searchQuery: _query.isEmpty ? null : _query,
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            icon: const Icon(Icons.copy, size: 16, color: NetSpecterTheme.textMuted),
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: '...'));
              ToastNotification.show(context, 'Copied!');
            },
            tooltip: 'Copy',
          ),
        ),
      ],
    );
  }

  bool _isActive(_DetailMatch? active, int tabIndex, _DetailSection section) {
    if (active == null) return false;
    return active.tabIndex == tabIndex && active.section == section;
  }
}

class _DetailMatch {
  const _DetailMatch({required this.tabIndex, required this.section});
  final int tabIndex;
  final _DetailSection section;
}

enum _DetailSection {
  overviewUrl,
  overviewMethod,
  overviewStatus,
  overviewDuration,
  overviewTime,
  overviewNote,
  requestHeaders,
  requestBody,
  responseHeaders,
  responseBody,
  errorType,
  errorMessage,
}

List<_DetailMatch> _computeMatches(
  RequestRecord record,
  String query,
  bool isWs,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];

  final matches = <_DetailMatch>[];

  bool contains(String? text) {
    if (text == null || text.isEmpty) return false;
    return text.toLowerCase().contains(q);
  }

  void addIf(bool cond, int tabIndex, _DetailSection section) {
    if (cond) {
      matches.add(_DetailMatch(tabIndex: tabIndex, section: section));
    }
  }

  // Overview
  addIf(contains(record.url), 0, _DetailSection.overviewUrl);
  addIf(contains(record.method), 0, _DetailSection.overviewMethod);
  addIf(
    contains(record.statusCode > 0 ? record.statusCode.toString() : 'N/A'),
    0,
    _DetailSection.overviewStatus,
  );
  addIf(
    contains('${record.durationMs} ms'),
    0,
    _DetailSection.overviewDuration,
  );
  addIf(
    contains(record.timestamp.toIso8601String()),
    0,
    _DetailSection.overviewTime,
  );
  if (record.isBodyTruncated) {
    addIf(
      contains(
        'Body truncated — response exceeded the size limit.',
      ),
      0,
      _DetailSection.overviewNote,
    );
  }

  if (!isWs) {
    // Request tab index 1
    addIf(
      contains(jsonEncode(record.requestHeaders)),
      1,
      _DetailSection.requestHeaders,
    );
    addIf(
      contains(record.requestBodyPreview),
      1,
      _DetailSection.requestBody,
    );

    // Response tab index 2
    addIf(
      contains(jsonEncode(record.responseHeaders)),
      2,
      _DetailSection.responseHeaders,
    );
    addIf(
      contains(record.responseBodyPreview),
      2,
      _DetailSection.responseBody,
    );

    // Error tab index 3
    addIf(
      contains(record.errorType ?? 'None'),
      3,
      _DetailSection.errorType,
    );
    addIf(
      contains(record.errorMessage ?? 'None'),
      3,
      _DetailSection.errorMessage,
    );
  }

  return matches;
}
