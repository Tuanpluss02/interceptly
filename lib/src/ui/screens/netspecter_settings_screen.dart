import 'package:flutter/material.dart';

import '../../storage/inspector_session.dart';

class NetSpecterSettingsScreen extends StatelessWidget {
  const NetSpecterSettingsScreen({
    super.key,
    required this.session,
  });

  final InspectorSession session;

  @override
  Widget build(BuildContext context) {
    final settings = session.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('NetSpecter Settings')),
      body: AnimatedBuilder(
        animation: session,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _SettingRow(
                label: 'Body offload threshold',
                value: '${settings.bodyOffloadThreshold} bytes',
              ),
              _SettingRow(
                label: 'Preview truncation',
                value: '${settings.previewTruncationBytes} bytes',
              ),
              _SettingRow(
                label: 'Max body storage',
                value: '${settings.maxBodyBytes} bytes',
              ),
              _SettingRow(
                label: 'Max queued captures',
                value: '${settings.maxQueuedEvents}',
              ),
              _SettingRow(
                label: 'Max entries in memory',
                value: '${settings.maxEntries}',
              ),
              const Divider(height: 32),
              _SettingRow(
                label: 'Captured entries',
                value: '${session.totalEntries}',
              ),
              _SettingRow(
                label: 'Dropped captures',
                value: '${session.droppedCount}',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}
