import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';

void main() {
  setUp(() async {
    await InspectorSession.resetForTesting();
  });

  tearDown(() async {
    await InspectorSession.resetForTesting();
  });

  test('public API exposes no release guard parameter', () async {
    final Interceptly Function({
      InterceptlySettings? settings,
    }) factory = Interceptly.new;
    final Future<void> Function({
      required GlobalKey<NavigatorState> navigatorKey,
      bool showFloatingButton,
      Widget? fabChild,
      Stream<void>? customTrigger,
      InterceptlySettings? settings,
    }) init = Interceptly.init;

    final controller = factory(
      settings: const InterceptlySettings(),
    );
    expect(controller.settings.maxEntries, 5000);
    expect(Interceptly.instance.isEnabled, isNotNull);
    expect(init, isNotNull);
    controller.dispose();
  });
}
