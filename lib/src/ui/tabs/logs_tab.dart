import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

class LogsTab extends StatelessWidget {
  const LogsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: _mockLogs.length,
      itemBuilder: (context, index) {
        final log = _mockLogs[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text(
                  log['time']!,
                  style: const TextStyle(
                    fontFamily: InterceptlyTheme.fontFamily,
                    package: InterceptlyTheme.fontPackage,
                    fontSize: 12,
                    color: InterceptlyTheme.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  log['message']!,
                  style: TextStyle(
                    fontFamily: InterceptlyTheme.fontFamily,
                    package: InterceptlyTheme.fontPackage,
                    fontSize: 13,
                    color: _getLogColor(log['type']!),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getLogColor(String type) {
    switch (type) {
      case 'error':
        return InterceptlyTheme.red400;
      case 'warning':
        return InterceptlyTheme.yellow400;
      case 'info':
      default:
        return InterceptlyTheme.textTertiary;
    }
  }
}

const _mockLogs = [
  {
    'time': '14:05:00',
    'message': 'Initializing Interceptly core...',
    'type': 'info',
  },
  {
    'time': '14:05:01',
    'message': 'Building widget tree... Success',
    'type': 'info',
  },
  {
    'time': '14:05:15',
    'message':
        'Unhandled Exception: Null check operator used on a null value\n at _ProfileState.build (profile_screen.dart:42)',
    'type': 'error',
  },
  {
    'time': '14:06:22',
    'message': 'Warning: Image size exceeds recommended limit.',
    'type': 'warning',
  },
];
