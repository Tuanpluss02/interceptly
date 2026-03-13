import 'package:flutter/material.dart';

import '../../model/index_entry.dart';

class HttpCallTile extends StatelessWidget {
  const HttpCallTile({
    super.key,
    required this.entry,
    this.onTap,
  });

  final IndexEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final statusCode = entry.statusCode;
    final statusText = statusCode > 0
        ? statusCode.toString()
        : (entry.hasError ? 'ERR' : '--');

    final durationText =
        entry.durationMs > 0 ? '${entry.durationMs} ms' : null;

    return ListTile(
      onTap: onTap,
      leading: _MethodBadge(method: entry.method),
      title: Text(
        entry.url,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('Status: $statusText'),
      trailing: durationText != null ? Text(durationText) : null,
    );
  }
}

class _MethodBadge extends StatelessWidget {
  const _MethodBadge({required this.method});

  final String method;

  static Color _colorFor(String method) {
    return switch (method.toUpperCase()) {
      'GET' => Colors.green,
      'POST' => Colors.blue,
      'PUT' => Colors.orange,
      'PATCH' => Colors.amber,
      'DELETE' => Colors.red,
      _ => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _colorFor(method).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _colorFor(method), width: 1),
      ),
      child: Text(
        method.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: _colorFor(method),
        ),
      ),
    );
  }
}
