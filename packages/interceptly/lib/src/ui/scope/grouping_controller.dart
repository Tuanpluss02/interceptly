import 'package:flutter/foundation.dart';

/// Manages domain grouping toggle and per-domain expand/collapse state.
class GroupingController extends ChangeNotifier {
  bool _enabled = false;
  final Map<String, bool> _expandedDomains = {};

  bool get enabled => _enabled;

  bool isExpanded(String domain) => _expandedDomains[domain] ?? true;

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }

  void toggleDomainExpanded(String domain) {
    _expandedDomains[domain] = !(_expandedDomains[domain] ?? true);
    notifyListeners();
  }

  void reset() {
    _expandedDomains.clear();
  }
}
