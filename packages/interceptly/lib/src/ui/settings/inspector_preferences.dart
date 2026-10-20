import 'package:flutter/material.dart';

import '../../model/network_protocol.dart';

/// Holds UI preferences that are independent of the capture session state.
///
/// Separated from data engine so that theme and decode settings do not
/// pollute the engine's single responsibility (capture lifecycle management).
class InterceptlyPreferences extends ChangeNotifier {
  InterceptlyPreferences({
    ThemeMode themeMode = ThemeMode.system,
    bool urlDecodeEnabled = true,
    int selectedTabIndex = 0,
  })  : _themeMode = themeMode,
        _urlDecodeEnabled = urlDecodeEnabled,
        _selectedTabIndex = selectedTabIndex;

  static InterceptlyPreferences _shared = InterceptlyPreferences();

  /// Shared preferences instance preserved across inspector screens.
  static InterceptlyPreferences get shared => _shared;

  /// Resets the shared preferences instance for testing isolation.
  static void resetSharedForTesting() {
    _shared = InterceptlyPreferences();
  }

  ThemeMode _themeMode;
  bool _urlDecodeEnabled;
  int _selectedTabIndex;

  ThemeMode get themeMode => _themeMode;
  bool get urlDecodeEnabled => _urlDecodeEnabled;
  int get selectedTabIndex => _selectedTabIndex;
  NetworkProtocol get selectedProtocol =>
      _selectedTabIndex == 1 ? NetworkProtocol.realtime : NetworkProtocol.rest;

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }

  void setUrlDecodeEnabled(bool value) {
    if (_urlDecodeEnabled == value) return;
    _urlDecodeEnabled = value;
    notifyListeners();
  }

  void setSelectedTabIndex(int index) {
    if (_selectedTabIndex == index) return;
    _selectedTabIndex = index;
    notifyListeners();
  }

  void setSelectedProtocol(NetworkProtocol protocol) {
    setSelectedTabIndex(protocol == NetworkProtocol.realtime ? 1 : 0);
  }
}
