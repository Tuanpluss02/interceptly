import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Internal widget that listens to the device accelerometer and calls
/// [onShake] when a shake gesture is detected.
///
/// A no-op on Flutter Web (accelerometer not available).
class ShakeDetector extends StatefulWidget {
  const ShakeDetector({
    super.key,
    required this.threshold,
    required this.minInterval,
    required this.onShake,
    required this.child,
  });

  /// Net acceleration magnitude (m/s²) needed to trigger a shake.
  final double threshold;

  /// Minimum time between consecutive shake events.
  final Duration minInterval;

  final VoidCallback onShake;
  final Widget child;

  @override
  State<ShakeDetector> createState() => _ShakeDetectorState();
}

class _ShakeDetectorState extends State<ShakeDetector> {
  StreamSubscription<UserAccelerometerEvent>? _sub;
  DateTime _lastShake = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _startListening();
  }

  void _startListening() {
    try {
      _sub = userAccelerometerEventStream(
        samplingPeriod: SensorInterval.uiInterval,
      ).listen(_onAccelerometer, onError: (_) {});
    } catch (_) {
      // Sensor not available on this device — silently ignore.
    }
  }

  void _onAccelerometer(UserAccelerometerEvent event) {
    final magnitude =
        sqrt(event.x * event.x + event.y * event.y + event.z * event.z);

    if (magnitude < widget.threshold) return;

    final now = DateTime.now();
    if (now.difference(_lastShake) < widget.minInterval) return;

    _lastShake = now;
    widget.onShake();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
