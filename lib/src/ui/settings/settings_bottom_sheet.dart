import 'package:flutter/material.dart';
import 'package:netspecter/src/ui/netspecter_theme.dart';

class SettingsBottomSheet extends StatefulWidget {
  const SettingsBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const SettingsBottomSheet(),
    );
  }

  @override
  State<SettingsBottomSheet> createState() => _SettingsBottomSheetState();
}

class _SettingsBottomSheetState extends State<SettingsBottomSheet> {
  bool _ignoreStaticAssets = true;
  String _maxRequests = '1000';
  bool _clearOnRestart = false;
  String _networkThrottling = 'Off';
  bool _mockingEnabled = true;
  bool _shakeToOpen = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: NetSpecterTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      child: Column(
        children: [
          // Handle & Header
          Container(
            padding: const EdgeInsets.only(top: 12.0, bottom: 12.0),
            decoration: BoxDecoration(
              color: NetSpecterTheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
            ),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Settings',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildSectionTitle('1. Network Filtering'),
                _buildSectionCard([
                  _SettingsTile(
                    icon: Icons.public,
                    title: 'Ignored Domains',
                    subtitle: 'Exclude specific URLs from logging',
                    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.image_outlined,
                    title: 'Ignore Static Assets',
                    subtitle: 'Hide .png, .jpg, .svg, .woff',
                    trailing: _CustomSwitch(
                      value: _ignoreStaticAssets,
                      activeColor: NetSpecterTheme.indigo500,
                      onChanged: (val) => setState(() => _ignoreStaticAssets = val),
                    ),
                  ),
                ]),
                
                const SizedBox(height: 24),
                _buildSectionTitle('2. Storage & Memory'),
                _buildSectionCard([
                  _SettingsTile(
                    icon: Icons.storage,
                    title: 'Max Requests Logged',
                    subtitle: 'Ring buffer size to save RAM',
                    trailing: _buildDropdown(
                      value: _maxRequests,
                      items: const ['500', '1000', '2000'],
                      onChanged: (val) => setState(() => _maxRequests = val!),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.cleaning_services_outlined,
                    title: 'Clear on App Restart',
                    subtitle: 'Auto wipe logs on fresh start',
                    trailing: _CustomSwitch(
                      value: _clearOnRestart,
                      activeColor: NetSpecterTheme.indigo500,
                      onChanged: (val) => setState(() => _clearOnRestart = val),
                    ),
                  ),
                ]),

                const SizedBox(height: 24),
                _buildSectionTitle('3. Advanced Tools'),
                _buildSectionCard([
                  _SettingsTile(
                    icon: Icons.hourglass_bottom,
                    title: 'Network Throttling',
                    subtitle: 'Simulate slow connection',
                    trailing: _buildDropdown(
                      value: _networkThrottling,
                      items: const ['Off', 'Delay +500ms', 'Delay +2000ms'],
                      onChanged: (val) => setState(() => _networkThrottling = val!),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.auto_fix_high,
                    title: 'Enable Response Mocking',
                    subtitle: 'Allow overriding API responses',
                    titleColor: NetSpecterTheme.purple100,
                    subtitleColor: NetSpecterTheme.purple300,
                    iconColor: NetSpecterTheme.purple400,
                    trailing: _CustomSwitch(
                      value: _mockingEnabled,
                      activeColor: NetSpecterTheme.purple500,
                      onChanged: (val) => setState(() => _mockingEnabled = val),
                    ),
                  ),
                ]),

                const SizedBox(height: 24),
                _buildSectionTitle('4. UI & Behavior'),
                _buildSectionCard([
                  _SettingsTile(
                    icon: Icons.screen_rotation,
                    title: 'Shake to Open',
                    subtitle: 'Trigger NetSpecter by shaking',
                    trailing: _CustomSwitch(
                      value: _shakeToOpen,
                      activeColor: NetSpecterTheme.indigo500,
                      onChanged: (val) => setState(() => _shakeToOpen = val),
                    ),
                  ),
                ]),
                
                const SizedBox(height: 48), // Padding bottom
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 12.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: NetSpecterTheme.indigo400,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildSectionCard(List<Widget> children) {
    final List<Widget> separatedChildren = [];
    for (int i = 0; i < children.length; i++) {
      separatedChildren.add(children[i]);
      if (i < children.length - 1) {
        separatedChildren.add(Divider(
          height: 1,
          color: Colors.white.withValues(alpha: 0.05),
          indent: 16, // Optional indent
        ));
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: NetSpecterTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: separatedChildren,
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: NetSpecterTheme.surface,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
          dropdownColor: NetSpecterTheme.surfaceContainer,
          style: const TextStyle(color: NetSpecterTheme.textSecondary, fontSize: 13),
          onChanged: onChanged,
          items: items.map<DropdownMenuItem<String>>((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;
  final Color? titleColor;
  final Color? subtitleColor;
  final Color? iconColor;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
    this.titleColor,
    this.subtitleColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: Colors.white.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? Colors.grey[400], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: titleColor ?? NetSpecterTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: subtitleColor ?? NetSpecterTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _CustomSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;

  const _CustomSwitch({
    required this.value,
    required this.onChanged,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeIn,
        width: 44,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.0),
          color: value ? activeColor : Colors.white.withValues(alpha: 0.1),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeIn,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2.0),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: Colors.black12, width: 0.5),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
