import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/settings/settings_bottom_sheet.dart';
import 'package:interceptly/src/ui/tabs/network_tab.dart';
import 'package:interceptly/src/ui/widgets/toast_notification.dart';

import '../../storage/inspector_session.dart';

/// Main inspector screen showing captured network calls and actions.
class InterceptlyScreen extends StatefulWidget {
  /// Creates the inspector screen bound to [session].
  const InterceptlyScreen({
    super.key,
    required this.session,
  });

  /// Session used to read and mutate captured data.
  final InspectorSession session;

  @override
  State<InterceptlyScreen> createState() => _InterceptlyScreenState();
}

class _InterceptlyScreenState extends State<InterceptlyScreen> {
  void _showSettings() {
    SettingsBottomSheet.show(context, widget.session);
  }

  void _clearLogs() {
    widget.session.clear();
    ToastNotification.show(context, 'Cleared all logs!');
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: InterceptlyTheme.darkTheme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Interceptly'),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearLogs,
              tooltip: 'Clear logs',
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: _showSettings,
              tooltip: 'Settings',
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1.0),
            child: Container(
              color: Colors.white.withValues(alpha: 0.05),
              height: 1.0,
            ),
          ),
        ),
        body: NetworkTab(session: widget.session),
      ),
    );
  }
}
