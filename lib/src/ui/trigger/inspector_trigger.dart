/// Defines how the inspector can be opened.
///
/// Multiple triggers can be combined in [InterceptlyConfig.triggers].
/// If `customTrigger` is passed to [InterceptlyOverlay], it opens the
/// inspector on every event regardless of this set.
enum InspectorTrigger {
  /// A draggable floating bug button (default).
  floatingButton,

  /// Shake the device to open the inspector.
  /// Uses the device accelerometer via the `sensors_plus` package.
  /// No-op on Flutter Web.
  shake,

  /// Long-press anywhere on a blank (non-interactive) area of the screen.
  longPress,
}
