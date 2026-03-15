import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

import '../../model/network_simulation.dart';
import '../../storage/inspector_session.dart';

/// Bottom-sheet UI for inspector runtime settings.
class SettingsBottomSheet extends StatefulWidget {
  /// Session to read/update URL decode and simulation options.
  final InspectorSession session;

  /// Creates a settings sheet bound to [session].
  const SettingsBottomSheet({super.key, required this.session});

  /// Opens the settings bottom sheet for [session].
  static Future<void> show(BuildContext context, InspectorSession session) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SettingsBottomSheet(session: session),
    );
  }

  @override
  State<SettingsBottomSheet> createState() => _SettingsBottomSheetState();
}

class _SettingsBottomSheetState extends State<SettingsBottomSheet> {
  bool _urlDecodeEnabled = true;
  late NetworkSimulationProfile _networkSimulation;

  static const String _customPresetName = 'Custom';

  List<NetworkSimulationProfile> get _presetProfiles =>
      NetworkSimulationProfile.presets;

  bool get _isCustomSelected => _selectedPresetName == _customPresetName;

  String get _selectedPresetName {
    final known = _presetProfiles.any((p) => p.name == _networkSimulation.name);
    return known ? _networkSimulation.name : _customPresetName;
  }

  @override
  void initState() {
    super.initState();
    // Assuming you want to read actual settings for other fields eventually,
    // right now just initialize URL decoding correctly.
    _urlDecodeEnabled = widget.session.urlDecodeEnabled;
    _networkSimulation = widget.session.networkSimulation;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: InterceptlyTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      child: Column(
        children: [
          // Handle & Header
          Container(
            padding: const EdgeInsets.only(top: 12.0, bottom: 12.0),
            decoration: BoxDecoration(
              color: InterceptlyTheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24.0)),
              border: Border(
                  bottom:
                      BorderSide(color: Colors.white.withValues(alpha: 0.05))),
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
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
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
                _buildSectionTitle('1. UI & Behavior'),
                _buildSectionCard([
                    _SettingsTile(
                    icon: Icons.link,
                    title: 'URL Decoding',
                    subtitle: 'Decode URL endpoints in list & detail',
                      trailing: _CustomSwitch(
                      value: _urlDecodeEnabled,
                      activeColor: InterceptlyTheme.indigo500,
                      onChanged: (val) {
                        setState(() => _urlDecodeEnabled = val);
                        widget.session.setUrlDecodeEnabled(val);
                      },
                    ),
                  ),
                ]),

                const SizedBox(height: 20),
                _buildSectionTitle('2. Network Simulation'),
                _buildSectionCard([
                  _SettingsTile(
                    icon: Icons.network_check,
                    title: 'Preset',
                    subtitle: _selectedPresetName,
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        dropdownColor: InterceptlyTheme.surfaceContainer,
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
                            .map((p) => DropdownMenuItem<String>(
                                  value: p.name,
                                  child: Text(
                                    p.name,
                                    style: const TextStyle(
                                      color: InterceptlyTheme.textPrimary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ))
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

                          final selected = _presetProfiles
                              .firstWhere((p) => p.name == value);
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
                      widget.session.setNetworkSimulation(next);
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
                      widget.session.setNetworkSimulation(next);
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
                      widget.session.setNetworkSimulation(next);
                    },
                  ),
                ],

                const SizedBox(height: 48), // Padding bottom
              ],
            ),
          ),
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
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: InterceptlyTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: InterceptlyTheme.textPrimary,
                ),
              ),
              Text(
                '${value.round()} $unit',
                style: const TextStyle(
                  fontFamily: InterceptlyTheme.fontFamily,
                  package: InterceptlyTheme.fontPackage,
                  fontSize: 12,
                  color: InterceptlyTheme.textMuted,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: InterceptlyTheme.indigo500,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              thumbColor: InterceptlyTheme.indigo400,
              overlayColor: InterceptlyTheme.indigo500.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value.clamp(0, max),
              min: 0,
              max: max,
              divisions: 100,
              onChanged: onChanged,
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
          color: InterceptlyTheme.indigo400,
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
        color: InterceptlyTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: separatedChildren,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      hoverColor: Colors.white.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey[400], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: InterceptlyTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: InterceptlyTheme.textMuted,
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
