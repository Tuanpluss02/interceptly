import 'package:flutter/material.dart';

import 'inspector_trigger.dart';

/// Configuration for how [NetSpecterOverlay] behaves.
class NetSpecterConfig {
  const NetSpecterConfig({
    this.triggers = const {InspectorTrigger.floatingButton},
    this.shakeThreshold = 15.0,
    this.shakeMinInterval = const Duration(milliseconds: 1000),
    this.longPressDuration = const Duration(milliseconds: 800),
    this.fabChild,
  });

  /// Which built-in triggers are active. Defaults to the floating button.
  final Set<InspectorTrigger> triggers;

  /// Minimum acceleration (m/s²) needed to register a shake.
  ///
  /// Uses [userAccelerometerEventStream] which already subtracts gravity,
  /// so this is net hand movement. 15 m/s² works well in practice.
  final double shakeThreshold;

  /// Cooldown between consecutive shake events.
  final Duration shakeMinInterval;

  /// How long to hold a long-press before the inspector opens.
  final Duration longPressDuration;

  /// Custom widget inside the floating button.
  /// Defaults to a white bug icon on a red circle.
  final Widget? fabChild;
}
