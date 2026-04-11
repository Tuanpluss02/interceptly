import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';

import 'src/example.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final clients = ExampleClients.create();
  final appNavigatorKey = GlobalKey<NavigatorState>();

  runApp(
    InterceptlyExampleApp(
      clients: clients,
      navigatorKey: appNavigatorKey,
    ),
  );

  Interceptly.attach(navigatorKey: appNavigatorKey);
}
