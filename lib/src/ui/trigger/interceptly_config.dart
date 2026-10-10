import 'package:flutter/material.dart';

import 'inspector_trigger.dart';

/// Configuration for [Interceptly.attach].
class InterceptlyConfig {
  const InterceptlyConfig({
    this.triggers = const {InspectorTrigger.floatingButton},
    this.fabChild,
  });

  /// Which built-in triggers are active. Defaults to the floating button.
  final Set<InspectorTrigger> triggers;

  /// Custom widget inside the floating button.
  /// Defaults to a white bug icon on a red circle.
  final Widget? fabChild;
}
