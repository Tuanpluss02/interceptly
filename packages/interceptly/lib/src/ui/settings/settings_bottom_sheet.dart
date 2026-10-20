import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

import '../../model/network_simulation.dart';
import '../overlay/floating_overlay_manager.dart';
import '../scope/interceptly_scope.dart';

/// Bottom-sheet UI for inspector runtime settings.
class SettingsBottomSheet extends StatefulWidget {
  /// Creates a settings sheet.
  const SettingsBottomSheet({super.key});

  /// Opens the settings bottom sheet.
  static Future<void> show(BuildContext context) {
    final scope = InterceptlyScope.read(context);
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: InterceptlyGlobalColor.transparent,
      builder: (_) => InterceptlyScope(
        controller: scope,
        child: const SettingsBottomSheet(),
      ),
    );
  }

  @override
  State<SettingsBottomSheet> createState() => _SettingsBottomSheetState();
}

class _SettingsBottomSheetState extends State<SettingsBottomSheet> {
  late InterceptlyScopeController _scope;
  bool _initialized = false;

  bool _urlDecodeEnabled = true;
  bool _hideFloatingButtonForSession = false;
  late NetworkSimulationProfile _networkSimulation;
  ThemeMode _themeMode = ThemeMode.system;

  static const String _customPresetName = 'Custom';

  List<NetworkSimulationProfile> get _presetProfiles =>
      NetworkSimulationProfile.presets;
  InterceptlyColors get _colors => InterceptlyTheme.colors;
  InterceptlyTypography get _typography => InterceptlyTheme.typography;

  bool get _isCustomSelected => _selectedPresetName == _customPresetName;

  String get _selectedPresetName {
    final known = _presetProfiles.any((p) => p.name == _networkSimulation.name);
    return known ? _networkSimulation.name : _customPresetName;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _scope = InterceptlyScope.read(context);
      _urlDecodeEnabled = _scope.preferences.urlDecodeEnabled;
      _networkSimulation = _scope.networkSimulation;
      _themeMode = _scope.preferences.themeMode;
      _hideFloatingButtonForSession =
          FloatingOverlayManager.instance.isHiddenForSession;
    }
  }

  @override
  Widget build(BuildContext context) {
    InterceptlyTheme.bind(context: context, themeMode: _themeMode);
    final theme = InterceptlyTheme.themeData(
      context: context,
      themeMode: _themeMode,
    );

    return Theme(
      data: theme,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: _colors.surfacePrimary,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(InterceptlyTheme.radius.lg * 2),
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.only(top: 12.0, bottom: 12.0),
              decoration: BoxDecoration(
                color: _colors.surfacePrimary,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(InterceptlyTheme.radius.lg * 2),
                ),
                border: Border(
                  bottom: BorderSide(color: InterceptlyTheme.dividerSubtle),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 6,
                    decoration: BoxDecoration(
                      color: InterceptlyTheme.controlMuted,
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Settings',
                          style: _typography.headlineLarge.copyWith(
                            color: _colors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: _colors.textSecondary),
                          onPressed: () => Navigator.of(context).pop(),
                          tooltip: 'Close settings',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                children: [
                  _buildSectionTitle('Display & Appearance'),
                  _buildSectionCard([
                    _SettingsTile(
                      icon: Icons.brightness_6_outlined,
                      title: 'Theme',
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<ThemeMode>(
                          dropdownColor: _colors.surfaceSecondary,
                          style: _typography.bodyMediumRegular.copyWith(
                            color: _colors.textPrimary,
                            fontSize: 12,
                          ),
                          iconEnabledColor: _colors.textSecondary,
                          iconDisabledColor: _colors.textTertiary,
                          value: _themeMode,
                          items: const [
                            DropdownMenuItem(
                              value: ThemeMode.system,
                              child: Text('System'),
                            ),
                            DropdownMenuItem(
                              value: ThemeMode.light,
                              child: Text('Light'),
                            ),
                            DropdownMenuItem(
                              value: ThemeMode.dark,
                              child: Text('Dark'),
                            ),
                          ],
                          onChanged: (mode) {
                            if (mode == null) return;
                            setState(() => _themeMode = mode);
                            _scope.preferences.setThemeMode(mode);
                          },
                        ),
                      ),
                    ),
                    _SettingsTile(
                      icon: Icons.link,
                      title: 'URL Decoding',
                      onTap: () {
                        final next = !_urlDecodeEnabled;
                        setState(() => _urlDecodeEnabled = next);
                        _scope.preferences.setUrlDecodeEnabled(next);
                      },
                      trailing: _CustomSwitch(
                        value: _urlDecodeEnabled,
                        activeColor: _colors.actionPrimary,
                        onChanged: (val) {
                          setState(() => _urlDecodeEnabled = val);
                          _scope.preferences.setUrlDecodeEnabled(val);
                        },
                      ),
                    ),
                    _SettingsTile(
                      icon: Icons.visibility_off_outlined,
                      title: 'Hide for This Session',
                      subtitle: 'Hides bug button until next app launch',
                      onTap: () {
                        final next = !_hideFloatingButtonForSession;
                        setState(() => _hideFloatingButtonForSession = next);
                        FloatingOverlayManager.instance
                            .setHiddenForSession(next);
                      },
                      trailing: _CustomSwitch(
                        value: _hideFloatingButtonForSession,
                        activeColor: _colors.actionPrimary,
                        onChanged: (val) {
                          setState(() => _hideFloatingButtonForSession = val);
                          FloatingOverlayManager.instance
                              .setHiddenForSession(val);
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  _buildSectionTitle('Network Simulation'),
                  _buildSectionCard([
                    _SettingsTile(
                      icon: Icons.network_check,
                      title: 'Preset',
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          dropdownColor: _colors.surfaceSecondary,
                          style: _typography.bodyMediumRegular.copyWith(
                            color: _colors.textPrimary,
                            fontSize: 12,
                          ),
                          iconEnabledColor: _colors.textSecondary,
                          iconDisabledColor: _colors.textTertiary,
                          value: _selectedPresetName,
                          items: [
                            ..._presetProfiles,
                            const NetworkSimulationProfile(
                              name: _customPresetName,
                              offline: false,
                              latencyMs: 0,
                              downloadKbps: 0,
                              uploadKbps: 0,
                            ),
                          ]
                              .map(
                                (p) => DropdownMenuItem<String>(
                                  value: p.name,
                                  child: Text(
                                    p.name,
                                    style:
                                        _typography.bodyMediumRegular.copyWith(
                                      color: _colors.textPrimary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            if (value == _customPresetName) {
                              final next = _networkSimulation.copyWith(
                                name: _customPresetName,
                              );
                              setState(() => _networkSimulation = next);
                              _scope.setNetworkSimulation(next);
                              return;
                            }

                            final selected = _presetProfiles.firstWhere(
                              (p) => p.name == value,
                            );
                            setState(() => _networkSimulation = selected);
                            _scope.setNetworkSimulation(selected);
                          },
                        ),
                      ),
                    ),
                  ]),
                  if (_isCustomSelected) ...[
                    const SizedBox(height: 12),
                    _buildThrottlingSlider(
                      title: 'Latency',
                      value: _networkSimulation.latencyMs.toDouble(),
                      max: 2000,
                      unit: 'ms',
                      onChanged: (v) {
                        final next = _networkSimulation.copyWith(
                          name: _customPresetName,
                          latencyMs: v.round(),
                        );
                        setState(() => _networkSimulation = next);
                      },
                      onChangeEnd: (v) {
                        _scope.setNetworkSimulation(_networkSimulation);
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildThrottlingSlider(
                      title: 'Download',
                      value: _networkSimulation.downloadKbps.toDouble(),
                      max: 50000,
                      unit: 'kbps',
                      onChanged: (v) {
                        final next = _networkSimulation.copyWith(
                          name: _customPresetName,
                          downloadKbps: v.round(),
                        );
                        setState(() => _networkSimulation = next);
                      },
                      onChangeEnd: (v) {
                        _scope.setNetworkSimulation(_networkSimulation);
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildThrottlingSlider(
                      title: 'Upload',
                      value: _networkSimulation.uploadKbps.toDouble(),
                      max: 50000,
                      unit: 'kbps',
                      onChanged: (v) {
                        final next = _networkSimulation.copyWith(
                          name: _customPresetName,
                          uploadKbps: v.round(),
                        );
                        setState(() => _networkSimulation = next);
                      },
                      onChangeEnd: (v) {
                        _scope.setNetworkSimulation(_networkSimulation);
                      },
                    ),
                  ],
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
      child: Text(
        title.toUpperCase(),
        style: _typography.labelSmallMedium.copyWith(
          color: _colors.textTertiary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildSectionCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: _colors.surfaceSecondary,
        borderRadius: BorderRadius.circular(InterceptlyTheme.radius.md),
        border: Border.all(color: InterceptlyTheme.dividerSubtle),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                color: InterceptlyTheme.dividerSubtle,
                indent: 44,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildThrottlingSlider({
    required String title,
    required double value,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: _colors.surfaceSecondary,
        borderRadius: BorderRadius.circular(InterceptlyTheme.radius.md),
        border: Border.all(color: InterceptlyTheme.dividerSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: _typography.bodyMediumMedium.copyWith(
                  color: _colors.textPrimary,
                ),
              ),
              Text(
                '${value.round()} $unit',
                style: _typography.labelSmallRegular.copyWith(
                  color: _colors.textSecondary,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: _colors.actionPrimary,
              inactiveTrackColor: InterceptlyTheme.controlMuted,
              thumbColor: _colors.actionPrimary,
              overlayColor: _colors.actionPrimary.withValues(alpha: 0.12),
              trackHeight: 3,
            ),
            child: Slider(
              value: value.clamp(0, max),
              min: 0,
              max: max,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = InterceptlyTheme.colors;
    final typography = InterceptlyTheme.typography;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(InterceptlyTheme.radius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: typography.bodyMediumMedium.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: typography.labelSmallRegular.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
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
    return Semantics(
      toggled: value,
      child: SizedBox(
        width: 48,
        height: 28,
        child: Center(
          child: GestureDetector(
            onTap: () => onChanged(!value),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeIn,
              width: 44,
              height: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.0),
                color: value ? activeColor : InterceptlyTheme.controlMuted,
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
                    color: InterceptlyGlobalColor.white,
                    border: Border.all(
                      color: InterceptlyGlobalColor.black12,
                      width: 0.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: InterceptlyGlobalColor.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
