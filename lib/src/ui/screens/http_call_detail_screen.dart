import 'package:flutter/material.dart';

import '../../model/index_entry.dart';
import '../../model/request_record.dart';
import '../../storage/inspector_session.dart';
import '../widgets/body_viewer.dart';

class HttpCallDetailScreen extends StatefulWidget {
  const HttpCallDetailScreen({
    super.key,
    required this.entry,
    required this.session,
  });

  final IndexEntry entry;
  final InspectorSession session;

  @override
  State<HttpCallDetailScreen> createState() => _HttpCallDetailScreenState();
}

class _HttpCallDetailScreenState extends State<HttpCallDetailScreen> {
  late Future<RequestRecord> _recordFuture;

  @override
  void initState() {
    super.initState();
    _recordFuture = widget.session.loadDetail(widget.entry);
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${entry.method} ${Uri.tryParse(entry.url)?.host ?? entry.url}',
          ),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Overview'),
              Tab(text: 'Request'),
              Tab(text: 'Response'),
              Tab(text: 'Error'),
            ],
          ),
        ),
        body: FutureBuilder<RequestRecord>(
          future: _recordFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            return _DetailTabView(record: snapshot.data!);
          },
        ),
      ),
    );
  }
}

class _DetailTabView extends StatelessWidget {
  const _DetailTabView({required this.record});

  final RequestRecord record;

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      children: <Widget>[
        // ── Overview ──────────────────────────────────────────────────────
        _Section(children: <Widget>[
          _Row(label: 'Method', value: record.method),
          _Row(label: 'URL', value: record.url),
          _Row(
            label: 'Status',
            value: record.statusCode > 0 ? record.statusCode.toString() : 'N/A',
          ),
          _Row(label: 'Duration', value: '${record.durationMs} ms'),
          _Row(label: 'Time', value: record.timestamp.toIso8601String()),
          if (record.isBodyTruncated)
            const _Row(
              label: 'Note',
              value: 'Body truncated — response exceeded the size limit.',
            ),
        ]),

        // ── Request ───────────────────────────────────────────────────────
        _Section(children: <Widget>[
          _Row(
            label: 'Content-Type',
            value: record.requestContentType ?? '(none)',
          ),
          _Row(
            label: 'Headers',
            value: _formatMap(record.requestHeaders),
          ),
          const SizedBox(height: 4),
          BodyViewer(
            body: record.requestBodyPreview,
            contentType: record.requestContentType,
          ),
        ]),

        // ── Response ──────────────────────────────────────────────────────
        _Section(children: <Widget>[
          _Row(
            label: 'Content-Type',
            value: record.responseContentType ?? '(none)',
          ),
          _Row(
            label: 'Headers',
            value: _formatMap(record.responseHeaders),
          ),
          const SizedBox(height: 4),
          BodyViewer(
            body: record.responseBodyPreview,
            contentType: record.responseContentType,
          ),
        ]),

        // ── Error ─────────────────────────────────────────────────────────
        _Section(children: <Widget>[
          _Row(label: 'Type', value: record.errorType ?? 'No error'),
          _Row(label: 'Message', value: record.errorMessage ?? 'No error'),
        ]),
      ],
    );
  }

  static String _formatMap(Map<String, String> map) {
    if (map.isEmpty) return '(empty)';
    return map.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: children.length,
      itemBuilder: (_, i) => children[i],
      separatorBuilder: (_, __) => const SizedBox(height: 12),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        SelectableText(value),
      ],
    );
  }
}
