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

  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  int _currentMatchIndex = 0;

  @override
  void initState() {
    super.initState();
    _recordFuture = widget.session.loadDetail(widget.entry);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
            final record = snapshot.data!;
            final matches = _computeMatches(record, _query);
            final totalMatches = matches.length;

            int effectiveIndex = _currentMatchIndex;
            if (totalMatches == 0) {
              effectiveIndex = 0;
            } else {
              effectiveIndex %= totalMatches;
              if (effectiveIndex < 0) {
                effectiveIndex += totalMatches;
              }
            }
            final activeLocation =
                totalMatches == 0 ? null : matches[effectiveIndex];

            return Column(
              children: <Widget>[
                _DetailSearchBar(
                  controller: _searchController,
                  query: _query,
                  totalMatches: totalMatches,
                  currentIndex:
                      totalMatches == 0 ? 0 : (effectiveIndex + 1),
                  onSubmitted: _onSearchSubmitted,
                  onClear: _onClearSearch,
                  onPrev: _onPrevMatch,
                  onNext: _onNextMatch,
                ),
                Expanded(
                  child: _DetailTabView(
                    record: record,
                    query: _query,
                    activeLocation: activeLocation,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _onSearchSubmitted(String value) {
    setState(() {
      _query = value.trim();
      _currentMatchIndex = 0;
    });
  }

  void _onClearSearch() {
    _searchController.clear();
    setState(() {
      _query = '';
      _currentMatchIndex = 0;
    });
  }

  void _onPrevMatch() {
    setState(() {
      _currentMatchIndex--;
    });
  }

  void _onNextMatch() {
    setState(() {
      _currentMatchIndex++;
    });
  }
}

class _DetailSearchBar extends StatelessWidget {
  const _DetailSearchBar({
    required this.controller,
    required this.query,
    required this.totalMatches,
    required this.currentIndex,
    required this.onSubmitted,
    required this.onClear,
    required this.onPrev,
    required this.onNext,
  });

  final TextEditingController controller;
  final String query;
  final int totalMatches;
  final int currentIndex;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: controller,
                onSubmitted: onSubmitted,
                onChanged: onSubmitted,
                decoration: InputDecoration(
                  labelText: 'Search in this request…',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Clear search',
                          onPressed: onClear,
                        ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              totalMatches == 0 ? '0 / 0' : '$currentIndex / $totalMatches',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              tooltip: 'Previous match',
              onPressed: totalMatches > 0 ? onPrev : null,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              tooltip: 'Next match',
              onPressed: totalMatches > 0 ? onNext : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailTabView extends StatelessWidget {
  const _DetailTabView({
    required this.record,
    required this.query,
    required this.activeLocation,
  });

  final RequestRecord record;
  final String query;
  final _DetailMatchLocation? activeLocation;

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();

    Widget overviewSection() {
      return _Section(
        children: <Widget>[
          _HighlightRow(
            label: 'Method',
            value: record.method,
            query: q,
            isActive: _isActive(0, _DetailSection.overviewMethod),
            onTap: () {},
          ),
          _HighlightRow(
            label: 'URL',
            value: record.url,
            query: q,
            isActive: _isActive(0, _DetailSection.overviewUrl),
            onTap: () {},
          ),
          _HighlightRow(
            label: 'Status',
            value:
                record.statusCode > 0 ? record.statusCode.toString() : 'N/A',
            query: q,
            isActive: _isActive(0, _DetailSection.overviewStatus),
            onTap: () {},
          ),
          _HighlightRow(
            label: 'Duration',
            value: '${record.durationMs} ms',
            query: q,
            isActive: _isActive(0, _DetailSection.overviewDuration),
            onTap: () {},
          ),
          _HighlightRow(
            label: 'Time',
            value: record.timestamp.toIso8601String(),
            query: q,
            isActive: _isActive(0, _DetailSection.overviewTime),
            onTap: () {},
          ),
          if (record.isBodyTruncated)
            _HighlightRow(
              label: 'Note',
              value: 'Body truncated — response exceeded the size limit.',
              query: q,
              isActive: _isActive(0, _DetailSection.overviewNote),
              onTap: () {},
            ),
        ],
      );
    }

    Widget requestSection() {
      final headersText = _formatMap(record.requestHeaders);
      return _Section(
        children: <Widget>[
          _HighlightRow(
            label: 'Content-Type',
            value: record.requestContentType ?? '(none)',
            query: q,
            isActive: _isActive(1, _DetailSection.requestContentType),
            onTap: () {},
          ),
          _HighlightRow(
            label: 'Headers',
            value: headersText,
            query: q,
            isActive: _isActive(1, _DetailSection.requestHeaders),
            onTap: () {},
          ),
          const SizedBox(height: 4),
          _BodySection(
            isActive: _isActive(1, _DetailSection.requestBody),
            tabIndex: 1,
            section: _DetailSection.requestBody,
            child: BodyViewer(
              body: record.requestBodyPreview,
              contentType: record.requestContentType,
            ),
          ),
        ],
      );
    }

    Widget responseSection() {
      final headersText = _formatMap(record.responseHeaders);
      return _Section(
        children: <Widget>[
          _HighlightRow(
            label: 'Content-Type',
            value: record.responseContentType ?? '(none)',
            query: q,
            isActive: _isActive(2, _DetailSection.responseContentType),
            onTap: () {},
          ),
          _HighlightRow(
            label: 'Headers',
            value: headersText,
            query: q,
            isActive: _isActive(2, _DetailSection.responseHeaders),
            onTap: () {},
          ),
          const SizedBox(height: 4),
          _BodySection(
            isActive: _isActive(2, _DetailSection.responseBody),
            tabIndex: 2,
            section: _DetailSection.responseBody,
            child: BodyViewer(
              body: record.responseBodyPreview,
              contentType: record.responseContentType,
            ),
          ),
        ],
      );
    }

    Widget errorSection() {
      final typeText = record.errorType ?? 'No error';
      final msgText = record.errorMessage ?? 'No error';
      return _Section(
        children: <Widget>[
          _HighlightRow(
            label: 'Type',
            value: typeText,
            query: q,
            isActive: _isActive(3, _DetailSection.errorType),
            onTap: () {},
          ),
          _HighlightRow(
            label: 'Message',
            value: msgText,
            query: q,
            isActive: _isActive(3, _DetailSection.errorMessage),
            onTap: () {},
          ),
        ],
      );
    }

    final children = <Widget>[
      overviewSection(),
      requestSection(),
      responseSection(),
      errorSection(),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final active = activeLocation;
      if (active != null) {
        final controller = DefaultTabController.of(context);
        if (controller.index != active.tabIndex) {
          controller.animateTo(active.tabIndex);
        }
      }
    });

    return TabBarView(
      children: children,
    );
  }

  bool _isActive(int tabIndex, _DetailSection section) {
    final active = activeLocation;
    return active != null &&
        active.tabIndex == tabIndex &&
        active.section == section;
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

class _HighlightRow extends StatelessWidget {
  const _HighlightRow({
    required this.label,
    required this.value,
    required this.query,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final String value;
  final String query;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lower = query.trim().toLowerCase();
    final spans = <TextSpan>[];

    if (lower.isEmpty) {
      spans.add(TextSpan(text: value));
    } else {
      final source = value;
      final sourceLower = source.toLowerCase();
      var start = 0;
      while (true) {
        final index = sourceLower.indexOf(lower, start);
        if (index < 0) {
          spans.add(TextSpan(text: source.substring(start)));
          break;
        }
        if (index > start) {
          spans.add(TextSpan(text: source.substring(start, index)));
        }
        spans.add(
          TextSpan(
            text: source.substring(index, index + lower.length),
            style: const TextStyle(
              backgroundColor: Color(0x80FFF59D),
            ),
          ),
        );
        start = index + lower.length;
      }
    }

    final key = GlobalKey();
    if (isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = key.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 200),
          );
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onTap,
          child: Container(
            key: key,
            color: isActive ? const Color(0x40FFF59D) : Colors.transparent,
            child: SelectableText.rich(
              TextSpan(children: spans),
            ),
          ),
        ),
      ],
    );
  }
}

class _BodySection extends StatelessWidget {
  const _BodySection({
    required this.child,
    required this.isActive,
    required this.tabIndex,
    required this.section,
  });

  final Widget child;
  final bool isActive;
  final int tabIndex;
  final _DetailSection section;

  @override
  Widget build(BuildContext context) {
    final key = GlobalKey();
    if (isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = key.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 200),
          );
        }
      });
    }

    return Container(key: key, child: child);
  }
}

enum _DetailSection {
  overviewMethod,
  overviewUrl,
  overviewStatus,
  overviewDuration,
  overviewTime,
  overviewNote,
  requestContentType,
  requestHeaders,
  requestBody,
  responseContentType,
  responseHeaders,
  responseBody,
  errorType,
  errorMessage,
}

class _DetailMatchLocation {
  const _DetailMatchLocation({
    required this.tabIndex,
    required this.section,
  });

  final int tabIndex;
  final _DetailSection section;
}

List<_DetailMatchLocation> _computeMatches(
  RequestRecord record,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];

  final matches = <_DetailMatchLocation>[];

  bool contains(String? text) {
    if (text == null || text.isEmpty) return false;
    return text.toLowerCase().contains(q);
  }

  void addIf(bool cond, int tab, _DetailSection section) {
    if (cond) {
      matches.add(_DetailMatchLocation(tabIndex: tab, section: section));
    }
  }

  // Overview
  addIf(contains(record.method), 0, _DetailSection.overviewMethod);
  addIf(contains(record.url), 0, _DetailSection.overviewUrl);
  addIf(
    contains(record.statusCode > 0 ? record.statusCode.toString() : 'N/A'),
    0,
    _DetailSection.overviewStatus,
  );
  addIf(contains('${record.durationMs} ms'), 0, _DetailSection.overviewDuration);
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

  // Request
  addIf(
    contains(record.requestContentType ?? '(none)'),
    1,
    _DetailSection.requestContentType,
  );
  addIf(
    contains(_DetailTabView._formatMap(record.requestHeaders)),
    1,
    _DetailSection.requestHeaders,
  );
  addIf(
    contains(record.requestBodyPreview),
    1,
    _DetailSection.requestBody,
  );

  // Response
  addIf(
    contains(record.responseContentType ?? '(none)'),
    2,
    _DetailSection.responseContentType,
  );
  addIf(
    contains(_DetailTabView._formatMap(record.responseHeaders)),
    2,
    _DetailSection.responseHeaders,
  );
  addIf(
    contains(record.responseBodyPreview),
    2,
    _DetailSection.responseBody,
  );

  // Error
  addIf(
    contains(record.errorType ?? 'No error'),
    3,
    _DetailSection.errorType,
  );
  addIf(
    contains(record.errorMessage ?? 'No error'),
    3,
    _DetailSection.errorMessage,
  );

  return matches;
}
