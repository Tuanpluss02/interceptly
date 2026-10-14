import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';

void main() {
  test('public API exposes no release guard parameter', () async {
    final Interceptly Function({
      InterceptlySettings? settings,
      InspectorSession? session,
    }) factory = Interceptly.new;
    final Future<void> Function({
      required GlobalKey<NavigatorState> navigatorKey,
      bool showFloatingButton,
      Widget? fabChild,
      Stream<void>? customTrigger,
      InterceptlySettings? settings,
      InspectorSession? session,
    }) init = Interceptly.init;

    final session = InspectorSession();
    final controller = factory(
      settings: const InterceptlySettings(),
      session: session,
    );
    expect(controller.settings.maxEntries, 5000);
    expect(Interceptly.instance.isEnabled, isNotNull);
    expect(init, isNotNull);
    controller.dispose();
    Interceptly.instance.dispose();
    await session.dispose();
  });
}
