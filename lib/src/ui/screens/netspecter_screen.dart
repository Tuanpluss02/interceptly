import 'package:flutter/material.dart';
import 'package:netspecter/src/ui/netspecter_theme.dart';
import 'package:netspecter/src/ui/settings/settings_bottom_sheet.dart';
import 'package:netspecter/src/ui/tabs/network_tab.dart';
import 'package:netspecter/src/ui/tabs/logs_tab.dart';
import 'package:netspecter/src/ui/widgets/toast_notification.dart';

import '../../storage/inspector_session.dart';

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
  int _currentIndex = 0;
  final PageController _pageController = PageController();

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _showSettings() {
    SettingsBottomSheet.show(context);
  }

  void _clearLogs() {
    widget.session.clear();
    ToastNotification.show(context, 'Cleared all logs!');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: NetSpecterTheme.darkTheme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('NetSpecter'),
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
        body: PageView(
          controller: _pageController,
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          children: [
            NetworkTab(session: widget.session),
            const LogsTab(),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 1, color: Colors.white.withValues(alpha: 0.05)),
            BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: _onTabTapped,
              items: [
                BottomNavigationBarItem(
                  icon: _CustomNavIcon(
                    icon: Icons.power_outlined,
                    isActive: _currentIndex == 0,
                  ),
                  label: 'Network',
                ),
                BottomNavigationBarItem(
                  icon: _CustomNavIcon(
                    icon: Icons.terminal_outlined,
                    isActive: _currentIndex == 1,
                  ),
                  label: 'App Logs',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomNavIcon extends StatelessWidget {
  final IconData icon;
  final bool isActive;

  const _CustomNavIcon({
    required this.icon,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (isActive)
          Positioned(
            top: -12, // Align with the top edge of BottomNavigationBar
            child: Container(
              width: 32,
              height: 3,
              decoration: const BoxDecoration(
                color: NetSpecterTheme.indigo500,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
          child: Icon(icon),
        ),
      ],
    );
  }
}
