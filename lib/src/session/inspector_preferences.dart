import 'package:flutter/material.dart';

/// Holds UI preferences that are independent of the capture session state.
///
/// Separated from [InspectorSession] so that theme and decode settings do not
/// pollute the session's single responsibility (capture lifecycle management).
class InspectorPreferences extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  bool _urlDecodeEnabled = true;

  ThemeMode get themeMode => _themeMode;
  bool get urlDecodeEnabled => _urlDecodeEnabled;

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
}
