import 'package:flutter/material.dart';

/// Configuration for [Interceptly.attach].
class InterceptlyConfig {
  const InterceptlyConfig({
    this.showFloatingButton = true,
    this.fabChild,
  });

  /// Whether to display the draggable floating bug button. Defaults to `true`.
  final bool showFloatingButton;

  /// Custom widget inside the floating button.
  /// Defaults to a white bug icon on a red circle.
  final Widget? fabChild;
}
