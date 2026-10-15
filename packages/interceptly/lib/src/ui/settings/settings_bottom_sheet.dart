import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

import '../../model/network_simulation.dart';
import '../../session/inspector_session_view.dart';
import '../overlay/floating_overlay_manager.dart';

/// Bottom-sheet UI for inspector runtime settings.
class SettingsBottomSheet extends StatefulWidget {
  /// Session to read/update URL decode and simulation options.
  final InspectorSessionView session;

  /// Creates a settings sheet bound to [session].
  const SettingsBottomSheet({super.key, required this.session});

  /// Opens the settings bottom sheet for [session].
  static Future<void> show(BuildContext context, InspectorSessionView session) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: InterceptlyGlobalColor.transparent,
      builder: (context) => SettingsBottomSheet(session: session),
    );
  }

  @override
  State<SettingsBottomSheet> createState() => _SettingsBottomSheetState();
}

class _SettingsBottomSheetState extends State<SettingsBottomSheet> {
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
  void initState() {
    super.initState();
    _urlDecodeEnabled = widget.session.preferences.urlDecodeEnabled;
    _networkSimulation = widget.session.networkSimulation;
    _themeMode = widget.session.preferences.themeMode;
    _hideFloatingButtonForSession =
        FloatingOverlayManager.instance.isHiddenForSession;
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
                          style: _typography.titleSmallBold.copyWith(
                            color: _colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildSectionTitle('UI & Behavior'),
                  _buildSectionCard([
                    _SettingsTile(
                      icon: Icons.dark_mode_outlined,
                      title: 'Theme Mode',
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
                          items: [
                            const DropdownMenuItem(
                              value: ThemeMode.system,
                              child: Text('System'),
                            ),
                            const DropdownMenuItem(
                              value: ThemeMode.light,
                              child: Text('Light'),
                            ),
                            const DropdownMenuItem(
                              value: ThemeMode.dark,
                              child: Text('Dark'),
                            ),
                          ],
                          onChanged: (mode) {
                            if (mode == null) return;
                            setState(() => _themeMode = mode);
                            widget.session.preferences.setThemeMode(mode);
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
                        widget.session.preferences.setUrlDecodeEnabled(next);
                      },
                      trailing: _CustomSwitch(
                        value: _urlDecodeEnabled,
                        activeColor: _colors.actionPrimary,
                        onChanged: (val) {
                          setState(() => _urlDecodeEnabled = val);
                          widget.session.preferences.setUrlDecodeEnabled(val);
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
                              widget.session.setNetworkSimulation(next);
                              return;
                            }

                            final selected = _presetProfiles.firstWhere(
                              (p) => p.name == value,
                            );
                            setState(() => _networkSimulation = selected);
                            widget.session.setNetworkSimulation(selected);
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
                        widget.session.setNetworkSimulation(_networkSimulation);
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
                        widget.session.setNetworkSimulation(_networkSimulation);
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
                        widget.session.setNetworkSimulation(_networkSimulation);
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

  Widget _buildThrottlingSlider({
    required String title,
    required double value,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _colors.surfaceSecondary,
        borderRadius: BorderRadius.circular(12.0),
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
                  fontSize: 13,
                  color: _colors.textPrimary,
                ),
              ),
              Text(
                '${value.round()} $unit',
                style: _typography.bodyMediumRegular.copyWith(
                  fontSize: 12,
                  color: InterceptlyTheme.textMuted,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: InterceptlyTheme.themeData(
              context: context,
              themeMode: _themeMode,
            ).sliderTheme,
            child: Slider(
              value: value.clamp(0, max),
              min: 0,
              max: max,
              divisions: 100,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
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
        style: _typography.bodyMediumBold.copyWith(
          fontSize: 12,
          color: _colors.actionSecondary,
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
        separatedChildren.add(
          Divider(
            height: 1,
            color: InterceptlyTheme.dividerSubtle,
            indent: 16,
          ),
        );
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: _colors.surfaceSecondary,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: InterceptlyTheme.dividerSubtle),
      ),
      child: Column(children: separatedChildren),
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
      hoverColor: InterceptlyTheme.hoverOverlay,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Icon(icon, color: colors.textTertiary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: typography.bodyMediumMedium.copyWith(
                        fontSize: 14,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: typography.bodySmallRegular.copyWith(
                          fontSize: 11,
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
      button: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
