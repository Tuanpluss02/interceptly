import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';

void main() {
  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  test('public API exposes no release guard parameter', () async {
    final Future<void> Function({
      required GlobalKey<NavigatorState> navigatorKey,
      bool showFloatingButton,
      Widget? fabChild,
      Stream<void>? customTrigger,
      InterceptlySettings? settings,
    }) init = Interceptly.init;

    Interceptly.instance.configure(const InterceptlySettings());
    expect(Interceptly.instance.settings.maxEntries, 5000);
    expect(Interceptly.instance.isEnabled, isNotNull);
    expect(init, isNotNull);
  });
}
