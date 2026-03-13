import 'package:flutter/material.dart';

import '../../model/http_call_filter.dart';
import '../../model/index_entry.dart';
import '../../storage/inspector_session.dart';
import '../widgets/http_call_tile.dart';
import 'http_call_detail_screen.dart';
import 'netspecter_settings_screen.dart';

class NetSpecterScreen extends StatefulWidget {
  const NetSpecterScreen({
    super.key,
    required this.session,
  });

  final InspectorSession session;

  @override
  State<NetSpecterScreen> createState() => _NetSpecterScreenState();
}

class _NetSpecterScreenState extends State<NetSpecterScreen> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _queryController = TextEditingController();

  String? _selectedMethod;
  String? _selectedStatus;

  InspectorSession get session => widget.session;

  @override
  void dispose() {
    _hostController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    session.applyFilter(
      HttpCallFilter(
        method: _selectedMethod,
        statusCode: _selectedStatus == null ? null : int.tryParse(_selectedStatus!),
        host: _hostController.text.trim().isEmpty ? null : _hostController.text.trim(),
        query: _queryController.text.trim().isEmpty ? null : _queryController.text.trim(),
      ),
    );
  }

  void _clearFilters() {
    _hostController.clear();
    _queryController.clear();
    setState(() {
      _selectedMethod = null;
      _selectedStatus = null;
    });
    session.clearFilter();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NetSpecterSettingsScreen(session: session),
      ),
    );
  }

  Future<void> _clearAll() async {
    await session.clear();
    if (mounted) _clearFilters();
  }

  void _openEntry(BuildContext context, IndexEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HttpCallDetailScreen(entry: entry, session: session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NetSpecter'),
        actions: <Widget>[
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _FilterBar(
            hostController: _hostController,
            queryController: _queryController,
            selectedMethod: _selectedMethod,
            selectedStatus: _selectedStatus,
            onMethodChanged: (v) => setState(() => _selectedMethod = v),
            onStatusChanged: (v) => setState(() => _selectedStatus = v),
            onApply: _applyFilters,
            onClear: _clearFilters,
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: session,
              builder: (context, _) {
                final entries = session.entries;

                if (entries.isEmpty) {
                  return const Center(
                    child: Text('No captured requests yet.'),
                  );
                }

                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return HttpCallTile(
                      key: ValueKey(entry.id),
                      entry: entry,
                      onTap: () => _openEntry(context, entry),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.hostController,
    required this.queryController,
    required this.selectedMethod,
    required this.selectedStatus,
    required this.onMethodChanged,
    required this.onStatusChanged,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController hostController;
  final TextEditingController queryController;
  final String? selectedMethod;
  final String? selectedStatus;
  final ValueChanged<String?> onMethodChanged;
  final ValueChanged<String?> onStatusChanged;
  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            TextField(
              controller: hostController,
              decoration: const InputDecoration(
                labelText: 'Host filter',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: queryController,
              decoration: const InputDecoration(
                labelText: 'Text query',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedMethod,
                    decoration: const InputDecoration(
                      labelText: 'Method',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: 'GET', child: Text('GET')),
                      DropdownMenuItem(value: 'POST', child: Text('POST')),
                      DropdownMenuItem(value: 'PUT', child: Text('PUT')),
                      DropdownMenuItem(value: 'PATCH', child: Text('PATCH')),
                      DropdownMenuItem(value: 'DELETE', child: Text('DELETE')),
                    ],
                    onChanged: onMethodChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: '200', child: Text('200')),
                      DropdownMenuItem(value: '201', child: Text('201')),
                      DropdownMenuItem(value: '400', child: Text('400')),
                      DropdownMenuItem(value: '401', child: Text('401')),
                      DropdownMenuItem(value: '404', child: Text('404')),
                      DropdownMenuItem(value: '500', child: Text('500')),
                      DropdownMenuItem(value: '503', child: Text('503')),
                    ],
                    onChanged: onStatusChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton(
                    onPressed: onApply,
                    child: const Text('Apply Filters'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onClear,
                    child: const Text('Clear'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
