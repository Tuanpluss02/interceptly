import 'package:flutter/material.dart';

import 'src/example.dart';

void main() {
  final clients = ExampleClients.create();
  final appNavigatorKey = GlobalKey<NavigatorState>();

  runApp(
    InterceptlyExampleApp(
      clients: clients,
      navigatorKey: appNavigatorKey,
    ),
  );
}
