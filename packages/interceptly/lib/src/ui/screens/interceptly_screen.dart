import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/filter/filter_panel.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/settings/settings_bottom_sheet.dart';
import 'package:interceptly/src/ui/tabs/network_tab.dart';
import 'package:interceptly/src/ui/tabs/realtime_list_tab.dart';
import 'package:interceptly/src/ui/widgets/interceptly_confirm_dialog.dart';
import 'package:interceptly/src/ui/widgets/toast_notification.dart';

import '../../engine/interceptly_engine.dart';
import '../scope/interceptly_scope.dart';

/// Main inspector screen showing captured network calls and actions.
class InterceptlyScreen extends StatefulWidget {
  /// Creates the inspector screen.
  ///
  /// Optionally accepts [controller] or [engine] for testing isolation.
  const InterceptlyScreen({
    super.key,
    this.controller,
    this.engine,
  });

  /// Optional pre-configured scope controller (primarily for testing).
  final InterceptlyScopeController? controller;

  /// Optional underlying engine (primarily for testing).
  final InterceptlyEngine? engine;

  @override
  State<InterceptlyScreen> createState() => _InterceptlyScreenState();
}

class _InterceptlyScreenState extends State<InterceptlyScreen> {
  late final InterceptlyScopeController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = InterceptlyScopeController(
        engine: widget.engine ?? InterceptlyEngine.instance,
      );
      _ownsController = true;
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _showSettings(BuildContext ctx) {
    SettingsBottomSheet.show(ctx);
  }

  void _showFilterPanel(BuildContext ctx) {
    final scope = InterceptlyScope.read(ctx);
    FilterPanel.show(
      context: ctx,
      currentFilter: scope.filter,
      availableDomains: scope.availableDomains,
      onFilterChanged: (newFilter) {
        scope.applyFilter(newFilter);
      },
    );
  }

  Future<void> _clearLogs(BuildContext ctx, {required bool realtime}) async {
    final scope = InterceptlyScope.read(ctx);
    final shouldClear = await InterceptlyConfirmDialog.show(
      ctx,
      title: realtime ? 'Clear realtime logs?' : 'Clear REST logs?',
      message: realtime
          ? 'This will remove all realtime connections and cannot be undone.'
          : 'This will remove all REST requests and cannot be undone.',
      confirmText: 'Clear',
      cancelText: 'Cancel',
    );

    if (!shouldClear) return;
    if (realtime) {
      await scope.clearRealtime();
    } else {
      await scope.clearRest();
    }
    if (!mounted) return;
    ToastNotification.show(
      realtime ? 'Cleared realtime logs!' : 'Cleared REST logs!',
      contextHint: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    return InterceptlyScope(
      controller: _controller,
      child: ListenableBuilder(
        listenable: _controller.preferences,
        builder: (context, _) {
          final themeMode = _controller.preferences.themeMode;
          InterceptlyTheme.bind(context: context, themeMode: themeMode);

          return Theme(
            data: InterceptlyTheme.themeData(
              context: context,
              themeMode: themeMode,
            ),
            child: Builder(
              builder: (themedContext) => ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  final isRealtime = _controller.isRealtimeActive;
                  final selectedTabIndex =
                      _controller.preferences.selectedTabIndex.clamp(0, 1);

                  return Scaffold(
                    appBar: AppBar(
                      title: const Text('Interceptly'),
                      actions: [
                        IconButton(
                          icon: Icon(_controller.groupingEnabled
                              ? Icons.group_work
                              : Icons.public),
                          onPressed: () => _controller
                              .toggleGrouping(!_controller.groupingEnabled),
                          tooltip: 'Group by domain',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _clearLogs(
                            themedContext,
                            realtime: isRealtime && selectedTabIndex == 1,
                          ),
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
                            groupingEnabled: _controller.groupingEnabled,
                            onShowFilterPanel: () =>
                                _showFilterPanel(themedContext),
                          )
                        : IndexedStack(
                            index: selectedTabIndex,
                            children: [
                              NetworkTab(
                                key: const ValueKey('tab_rest'),
                                groupingEnabled: _controller.groupingEnabled,
                                onShowFilterPanel: () =>
                                    _showFilterPanel(themedContext),
                              ),
                              const RealtimeListTab(
                                key: ValueKey('tab_realtime'),
                              ),
                            ],
                          ),
                    bottomNavigationBar: isRealtime
                        ? NavigationBar(
                            selectedIndex: selectedTabIndex,
                            onDestinationSelected: (i) =>
                                _controller.preferences.setSelectedTabIndex(i),
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
      ),
    );
  }
}
