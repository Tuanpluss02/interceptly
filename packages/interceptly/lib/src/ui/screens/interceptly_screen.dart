import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/filter/filter_panel.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/settings/settings_bottom_sheet.dart';
import 'package:interceptly/src/ui/tabs/network_tab.dart';
import 'package:interceptly/src/ui/widgets/interceptly_confirm_dialog.dart';
import 'package:interceptly/src/ui/widgets/toast_notification.dart';

import '../../model/network_protocol.dart';
import '../../session/inspector_session.dart';
import '../../session/inspector_session_view.dart';

/// Main inspector screen showing captured network calls and actions.
class InterceptlyScreen extends StatefulWidget {
  /// Creates the inspector screen bound to [session] (defaults to [InspectorSession.instance]).
  InterceptlyScreen({super.key, InspectorSessionView? session})
      : session = session ?? InspectorSession.instance;

  /// Session used to read and mutate captured data.
  final InspectorSessionView session;

  @override
  State<InterceptlyScreen> createState() => _InterceptlyScreenState();
}

class _InterceptlyScreenState extends State<InterceptlyScreen> {
  int _selectedTabIndex = 0;

  void _showSettings(BuildContext ctx) {
    SettingsBottomSheet.show(ctx, widget.session);
  }

  void _showFilterPanel(BuildContext ctx) {
    FilterPanel.show(
      context: ctx,
      currentFilter: widget.session.filter,
      availableDomains: widget.session.availableDomains,
      onFilterChanged: (newFilter) {
        widget.session.applyFilter(newFilter);
      },
    );
  }

  Future<void> _clearLogs(BuildContext ctx) async {
    final shouldClear = await InterceptlyConfirmDialog.show(
      ctx,
      title: 'Clear all logs?',
      message: 'This action cannot be undone.',
      confirmText: 'Clear',
      cancelText: 'Cancel',
    );

    if (!shouldClear) return;
    widget.session.clear();
    if (!mounted) return;
    ToastNotification.show('Cleared all logs!', contextHint: context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session.preferences,
      builder: (context, _) {
        final themeMode = widget.session.preferences.themeMode;
        InterceptlyTheme.bind(context: context, themeMode: themeMode);

        return Theme(
          data: InterceptlyTheme.themeData(
            context: context,
            themeMode: themeMode,
          ),
          child: Builder(
            builder: (themedContext) => ListenableBuilder(
              listenable: widget.session,
              builder: (context, _) {
                final isRealtime = widget.session.isRealtimeActive;

                return Scaffold(
                  appBar: AppBar(
                    title: const Text('Interceptly'),
                    actions: [
                      IconButton(
                        icon: Icon(widget.session.groupingEnabled
                            ? Icons.group_work
                            : Icons.public),
                        onPressed: () => widget.session
                            .toggleGrouping(!widget.session.groupingEnabled),
                        tooltip: 'Group by domain',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _clearLogs(themedContext),
                        tooltip: 'Clear logs',
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () => _showSettings(themedContext),
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
                  body: !isRealtime
                      ? NetworkTab(
                          session: widget.session,
                          protocol: NetworkProtocol.rest,
                          groupingEnabled: widget.session.groupingEnabled,
                          onShowFilterPanel: () =>
                              _showFilterPanel(themedContext),
                        )
                      : IndexedStack(
                          index: _selectedTabIndex,
                          children: [
                            NetworkTab(
                              key: const ValueKey('tab_rest'),
                              session: widget.session,
                              protocol: NetworkProtocol.rest,
                              groupingEnabled: widget.session.groupingEnabled,
                              onShowFilterPanel: () =>
                                  _showFilterPanel(themedContext),
                            ),
                            NetworkTab(
                              key: const ValueKey('tab_realtime'),
                              session: widget.session,
                              protocol: NetworkProtocol.realtime,
                              groupingEnabled: widget.session.groupingEnabled,
                              onShowFilterPanel: () =>
                                  _showFilterPanel(themedContext),
                            ),
                          ],
                        ),
                  bottomNavigationBar: isRealtime
                      ? NavigationBar(
                          selectedIndex: _selectedTabIndex,
                          onDestinationSelected: (i) =>
                              setState(() => _selectedTabIndex = i),
                          destinations: const [
                            NavigationDestination(
                              icon: Icon(Icons.http),
                              label: 'REST',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.cable),
                              label: 'Realtime',
                            ),
                          ],
                        )
                      : null,
                );
              },
            ),
          ),
        );
      },
    );
  }
}
