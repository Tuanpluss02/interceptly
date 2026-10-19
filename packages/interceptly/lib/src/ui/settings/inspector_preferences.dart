import 'package:flutter/material.dart';

import '../../model/network_protocol.dart';

/// Holds UI preferences that are independent of the capture session state.
///
/// Separated from data engine so that theme and decode settings do not
/// pollute the engine's single responsibility (capture lifecycle management).
class InterceptlyPreferences extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  bool _urlDecodeEnabled = true;
  int _selectedTabIndex = 0;

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
