import 'json_viewer_style.dart';

/// Manages expand/collapse state for collapsible nodes in the JSON viewer.
///
/// Tracks explicit user toggles, nodes auto-expanded by active search matches,
/// and nodes explicitly collapsed by the user (which shouldn't be auto-expanded).
class JsonExpansionState {
  /// User's explicit overrides for node paths (e.g. `$.data.items[0]` -> true/false).
  final Map<String, bool> _expandState = {};

  /// Paths auto-expanded because they contain the currently active search match.
  final Set<String> _searchAutoExpanded = {};

  /// Paths explicitly collapsed by the user, preventing search auto-expansion.
  final Set<String> _userCollapsedPaths = {};

  /// When true, all nodes except root start collapsed (for large documents > 1500 lines).
  bool forceCollapse = false;

  /// Returns whether node at [path] with [childCount] is currently expanded.
  bool isExpanded(String path, int childCount) {
    if (_searchAutoExpanded.contains(path)) return true;
    final explicit = _expandState[path];
    if (explicit != null) return explicit;
    if (forceCollapse) return path == r'$';
    return childCount <= JsonViewerMetrics.defaultExpandChildLimit;
  }

  /// Toggles node at [path] and updates user-collapsed / auto-expanded tracking.
  void toggle(String path, int childCount) {
    final wasExpanded = isExpanded(path, childCount);
    _expandState[path] = !wasExpanded;
    _searchAutoExpanded.remove(path);
    if (wasExpanded) {
      _userCollapsedPaths.add(path);
    } else {
      _userCollapsedPaths.remove(path);
    }
  }

  /// Set of paths explicitly collapsed by the user.
  Set<String> get userCollapsedPaths => Set.unmodifiable(_userCollapsedPaths);

  /// Explicit expand/collapse states set by the user.
  Map<String, bool> get explicitState => Map.unmodifiable(_expandState);

  /// Whether the user has explicitly collapsed the node at [path].
  bool isUserCollapsed(String path) => _userCollapsedPaths.contains(path);

  /// Marks the node at [path] as explicitly collapsed by the user.
  void markUserCollapsed(String path) => _userCollapsedPaths.add(path);

  /// Sets an explicit expansion state for [path].
  void setExplicitState(String path, bool expanded) =>
      _expandState[path] = expanded;

  /// Auto-expands the node at [path] to reveal an active search match.
  void markAutoExpanded(String path) {
    _searchAutoExpanded.add(path);
  }

  /// Clears auto-expanded search nodes (e.g. when search query changes).
  void clearSearchAutoExpanded() {
    _searchAutoExpanded.clear();
  }

  /// Resets search tracking (both auto-expanded and user-collapsed paths)
  /// when the search query changes.
  void resetSearch() {
    _searchAutoExpanded.clear();
    _userCollapsedPaths.clear();
  }

  /// Clears all state (used when data changes completely).
  void clear() {
    _expandState.clear();
    _searchAutoExpanded.clear();
    _userCollapsedPaths.clear();
    forceCollapse = false;
  }
}
