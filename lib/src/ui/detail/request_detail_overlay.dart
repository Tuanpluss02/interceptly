import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:netspecter/src/ui/netspecter_theme.dart';
import 'package:netspecter/src/ui/widgets/json_viewer.dart';
import 'package:netspecter/src/ui/widgets/toast_notification.dart';

class RequestDetailOverlay extends StatefulWidget {
  final Map<String, dynamic> request;

  const RequestDetailOverlay({super.key, required this.request});

  @override
  State<RequestDetailOverlay> createState() => _RequestDetailOverlayState();
}

class _RequestDetailOverlayState extends State<RequestDetailOverlay>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final isWs = widget.request['method'] == 'WS';
    _tabController = TabController(length: isWs ? 2 : 3, vsync: this);
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

  @override
  Widget build(BuildContext context) {
    final isWs = widget.request['method'] == 'WS';
    final sStyle = NetSpecterTheme.getStatusStyle(widget.request['status']);

    return Scaffold(
      backgroundColor: NetSpecterTheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.request['path'],
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
              '${widget.request['status']} ${widget.request['status'] == 200 ? 'OK' : ''}',
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
                tabs: isWs
                    ? const [
                        Tab(text: 'Overview'),
                        Tab(text: 'Messages'),
                      ]
                    : const [
                        Tab(text: 'Overview'),
                        Tab(text: 'Request'),
                        Tab(text: 'Response'),
                      ],
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Detail Search Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            decoration: BoxDecoration(
              color: NetSpecterTheme.surface,
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search in details...',
                hintStyle: const TextStyle(color: NetSpecterTheme.textMuted, fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: NetSpecterTheme.textMuted, size: 20),
                filled: true,
                fillColor: NetSpecterTheme.surfaceContainer,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10.0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: const BorderSide(color: NetSpecterTheme.indigo500, width: 1.0),
                ),
              ),
              style: const TextStyle(color: NetSpecterTheme.textSecondary, fontSize: 14),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  children: isWs
                      ? [
                          _buildOverviewTab(),
                          _buildMessagesTab(),
                        ]
                      : [
                          _buildOverviewTab(),
                          _buildRequestTab(),
                          _buildResponseTab(),
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
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30.0),
                        ),
                        elevation: 8,
                        shadowColor: NetSpecterTheme.indigo500.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final req = widget.request;
    final mStyle = NetSpecterTheme.getMethodStyle(req['method']);

    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100), // padding for FAB
      children: [
        _buildOverviewRow('URL', req['domain'] != null ? '${req['domain']}${req['path']}' : req['path']),
        const SizedBox(height: 16),
        _buildOverviewRow(
            'Method',
            req['method'],
            valueStyle: TextStyle(
              color: mStyle.text,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: 12,
            )),
        const SizedBox(height: 16),
        _buildOverviewRow('Duration', req['duration'].toString()),
        const SizedBox(height: 16),
        _buildOverviewRow('Time', req['time']),
      ],
    );
  }

  Widget _buildOverviewRow(String label, String value, {TextStyle? valueStyle}) {
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
            style: valueStyle ??
                const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: NetSpecterTheme.textSecondary,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestTab() {
    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
      children: [
        _buildSectionHeader('Request Headers'),
        _buildJsonBox(widget.request['reqHeaders']), // Should be map, mock handles this later
        const SizedBox(height: 24),
        _buildSectionHeader('Request Body', color: NetSpecterTheme.indigo400),
        _buildJsonBox(widget.request['reqBody']),
      ],
    );
  }

  Widget _buildResponseTab() {
    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
      children: [
        _buildSectionHeader('Response Headers'),
        _buildJsonBox(widget.request['resHeaders']),
        const SizedBox(height: 24),
        _buildSectionHeader('Response Body', color: NetSpecterTheme.green400),
        _buildJsonBox(widget.request['resBody']),
      ],
    );
  }

  Widget _buildMessagesTab() {
    final messages = widget.request['messages'] as List<dynamic>? ?? [];

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
                child: JsonViewer(data: msg['data']),
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

  Widget _buildJsonBox(dynamic data) {
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
          child: JsonViewer(data: data),
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
}
