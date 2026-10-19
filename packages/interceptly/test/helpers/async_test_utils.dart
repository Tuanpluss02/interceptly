import 'dart:async';

import 'package:interceptly/src/engine/interceptly_engine.dart';

/// Repeatedly polls [condition] every [step] until it returns true or [timeout] elapses.
///
/// Throws [TimeoutException] if the condition is not met before [timeout].
Future<void> waitForCondition(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 4),
  Duration step = const Duration(milliseconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Condition was not met within $timeout');
    }
    await Future<void>.delayed(step);
  }
}

/// Flushes coalesced notification timer on [engine] and pumps the event loop.
Future<void> flushEngineNotifications(InterceptlyEngine engine) async {
  engine.flushPendingNotifications();
  await Future<void>.delayed(Duration.zero);
}
