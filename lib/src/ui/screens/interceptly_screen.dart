import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/settings/settings_bottom_sheet.dart';
import 'package:interceptly/src/ui/tabs/network_tab.dart';
import 'package:interceptly/src/ui/widgets/interceptly_confirm_dialog.dart';
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

  Future<void> _clearLogs() async {
    final shouldClear = await InterceptlyConfirmDialog.show(
      context,
      title: 'Clear all logs?',
      message: 'This action cannot be undone.',
      confirmText: 'Clear',
      cancelText: 'Cancel',
    );

    if (!shouldClear) return;
    widget.session.clear();
    if (!mounted) return;
    ToastNotification.show(context, 'Cleared all logs!');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        InterceptlyTheme.bind(
          context: context,
          themeMode: widget.session.themeMode,
        );

        return Theme(
          data: InterceptlyTheme.themeData(
            context: context,
            themeMode: widget.session.themeMode,
          ),
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
                  color: InterceptlyTheme.dividerSubtle,
                  height: 1.0,
                ),
              ),
            ),
            body: NetworkTab(session: widget.session),
          ),
        );
      },
    );
  }
}
