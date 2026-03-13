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
  List<_DetailMatchLocation> _matches = const [];
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
            final activeLocation =
                _matches.isEmpty ? null : _matches[_currentMatchIndex];
            return Column(
              children: <Widget>[
                _DetailSearchBar(
                  controller: _searchController,
                  query: _query,
                  totalMatches: _matches.length,
                  currentIndex:
                      _matches.isEmpty ? 0 : _currentMatchIndex + 1,
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
                    onMatchesChanged: _onMatchesChanged,
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
      _matches = const [];
      _currentMatchIndex = 0;
    });
  }

  void _onPrevMatch() {
    if (_matches.isEmpty) return;
    setState(() {
      _currentMatchIndex =
          (_currentMatchIndex - 1 + _matches.length) % _matches.length;
    });
  }

  void _onNextMatch() {
    if (_matches.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _matches.length;
    });
  }

  void _onMatchesChanged(List<_DetailMatchLocation> matches) {
    if (_query.isEmpty) {
      if (_matches.isEmpty) return;
      setState(() {
        _matches = const [];
        _currentMatchIndex = 0;
      });
      return;
    }
    setState(() {
      _matches = matches;
      if (_matches.isEmpty) {
        _currentMatchIndex = 0;
      } else if (_currentMatchIndex >= _matches.length) {
        _currentMatchIndex = 0;
      }
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
    required this.onMatchesChanged,
  });

  final RequestRecord record;
  final String query;
  final _DetailMatchLocation? activeLocation;
  final ValueChanged<List<_DetailMatchLocation>> onMatchesChanged;

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final matches = <_DetailMatchLocation>[];

    bool contains(String? text) {
      if (text == null || text.isEmpty || q.isEmpty) return false;
      return text.toLowerCase().contains(q);
    }

    Widget overviewSection() {
      return _Section(
        children: <Widget>[
          _HighlightRow(
            label: 'Method',
            value: record.method,
            query: q,
            isActive: _isActive(0, _DetailSection.overviewMethod),
            register: (hasMatch) => _registerMatch(
              matches,
              tabIndex: 0,
              section: _DetailSection.overviewMethod,
              hasMatch: hasMatch,
            ),
          ),
          _HighlightRow(
            label: 'URL',
            value: record.url,
            query: q,
            isActive: _isActive(0, _DetailSection.overviewUrl),
            register: (hasMatch) => _registerMatch(
              matches,
              tabIndex: 0,
              section: _DetailSection.overviewUrl,
              hasMatch: hasMatch,
            ),
          ),
          _HighlightRow(
            label: 'Status',
            value:
                record.statusCode > 0 ? record.statusCode.toString() : 'N/A',
            query: q,
            isActive: _isActive(0, _DetailSection.overviewStatus),
            register: (hasMatch) => _registerMatch(
              matches,
              tabIndex: 0,
              section: _DetailSection.overviewStatus,
              hasMatch: hasMatch,
            ),
          ),
          _HighlightRow(
            label: 'Duration',
            value: '${record.durationMs} ms',
            query: q,
            isActive: _isActive(0, _DetailSection.overviewDuration),
            register: (hasMatch) => _registerMatch(
              matches,
              tabIndex: 0,
              section: _DetailSection.overviewDuration,
              hasMatch: hasMatch,
            ),
          ),
          _HighlightRow(
            label: 'Time',
            value: record.timestamp.toIso8601String(),
            query: q,
            isActive: _isActive(0, _DetailSection.overviewTime),
            register: (hasMatch) => _registerMatch(
              matches,
              tabIndex: 0,
              section: _DetailSection.overviewTime,
              hasMatch: hasMatch,
            ),
          ),
          if (record.isBodyTruncated)
            _HighlightRow(
              label: 'Note',
              value: 'Body truncated — response exceeded the size limit.',
              query: q,
              isActive: _isActive(0, _DetailSection.overviewNote),
              register: (hasMatch) => _registerMatch(
                matches,
                tabIndex: 0,
                section: _DetailSection.overviewNote,
                hasMatch: hasMatch,
              ),
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
            register: (hasMatch) => _registerMatch(
              matches,
              tabIndex: 1,
              section: _DetailSection.requestContentType,
              hasMatch: hasMatch,
            ),
          ),
          _HighlightRow(
            label: 'Headers',
            value: headersText,
            query: q,
            isActive: _isActive(1, _DetailSection.requestHeaders),
            register: (hasMatch) => _registerMatch(
              matches,
              tabIndex: 1,
              section: _DetailSection.requestHeaders,
              hasMatch: hasMatch,
            ),
          ),
          const SizedBox(height: 4),
          _BodySection(
            child: BodyViewer(
              body: record.requestBodyPreview,
              contentType: record.requestContentType,
            ),
            hasMatch: contains(record.requestBodyPreview),
            isActive: _isActive(1, _DetailSection.requestBody),
            tabIndex: 1,
            section: _DetailSection.requestBody,
            matches: matches,
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
            register: (hasMatch) => _registerMatch(
              matches,
              tabIndex: 2,
              section: _DetailSection.responseContentType,
              hasMatch: hasMatch,
            ),
          ),
          _HighlightRow(
            label: 'Headers',
            value: headersText,
            query: q,
            isActive: _isActive(2, _DetailSection.responseHeaders),
            register: (hasMatch) => _registerMatch(
              matches,
              tabIndex: 2,
              section: _DetailSection.responseHeaders,
              hasMatch: hasMatch,
            ),
          ),
          const SizedBox(height: 4),
          _BodySection(
            child: BodyViewer(
              body: record.responseBodyPreview,
              contentType: record.responseContentType,
            ),
            hasMatch: contains(record.responseBodyPreview),
            isActive: _isActive(2, _DetailSection.responseBody),
            tabIndex: 2,
            section: _DetailSection.responseBody,
            matches: matches,
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
            register: (hasMatch) => _registerMatch(
              matches,
              tabIndex: 3,
              section: _DetailSection.errorType,
              hasMatch: hasMatch,
            ),
          ),
          _HighlightRow(
            label: 'Message',
            value: msgText,
            query: q,
            isActive: _isActive(3, _DetailSection.errorMessage),
            register: (hasMatch) => _registerMatch(
              matches,
              tabIndex: 3,
              section: _DetailSection.errorMessage,
              hasMatch: hasMatch,
            ),
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
      onMatchesChanged(q.isEmpty ? const [] : matches);
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

  static void _registerMatch(
    List<_DetailMatchLocation> matches, {
    required int tabIndex,
    required _DetailSection section,
    required bool hasMatch,
  }) {
    if (!hasMatch) return;
    matches.add(
      _DetailMatchLocation(tabIndex: tabIndex, section: section),
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

class _HighlightRow extends StatelessWidget {
  const _HighlightRow({
    required this.label,
    required this.value,
    required this.query,
    required this.isActive,
    required this.register,
  });

  final String label;
  final String value;
  final String query;
  final bool isActive;
  final ValueChanged<bool> register;

  @override
  Widget build(BuildContext context) {
    final lower = query.trim().toLowerCase();
    final spans = <TextSpan>[];

    bool hasMatch = false;
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
        hasMatch = true;
        start = index + lower.length;
      }
    }

    register(hasMatch);

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
        Container(
          key: key,
          color: isActive ? const Color(0x40FFF59D) : Colors.transparent,
          child: SelectableText.rich(
            TextSpan(children: spans),
          ),
        ),
      ],
    );
  }
}

class _BodySection extends StatelessWidget {
  const _BodySection({
    required this.child,
    required this.hasMatch,
    required this.isActive,
    required this.tabIndex,
    required this.section,
    required this.matches,
  });

  final Widget child;
  final bool hasMatch;
  final bool isActive;
  final int tabIndex;
  final _DetailSection section;
  final List<_DetailMatchLocation> matches;

  @override
  Widget build(BuildContext context) {
    if (hasMatch) {
      matches.add(
        _DetailMatchLocation(tabIndex: tabIndex, section: section),
      );
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
