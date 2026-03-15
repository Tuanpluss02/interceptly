import 'package:example/src/example.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('example app renders integration actions', (
    WidgetTester tester,
  ) async {
    final clients = ExampleClients.create();

    await tester.pumpWidget(
      InterceptlyExampleApp(
        clients: clients,
        navigatorKey: GlobalKey<NavigatorState>(),
      ),
    );

    expect(find.text('Interceptly Example'), findsOneWidget);
    expect(find.text('Run Dio GET'), findsOneWidget);
    expect(find.text('Run HTTP GET'), findsOneWidget);
    expect(find.text('Run Chopper GET'), findsOneWidget);
    expect(find.text('Run Error Request'), findsOneWidget);
  });
}
