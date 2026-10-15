import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';

import 'src/example.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final server = ExampleLocalServer();
  final baseUrl = await server.start();

  final clients = ExampleClients.create(baseUrl: baseUrl);
  final appNavigatorKey = GlobalKey<NavigatorState>();

  runApp(
    InterceptlyExampleApp(
      clients: clients,
      navigatorKey: appNavigatorKey,
      server: server,
    ),
  );

  Interceptly.init(
    navigatorKey: appNavigatorKey,
    settings: InterceptlySettings(
      maxBodyBytes: 50 * 1024 * 1024,
      maxUiPreviewBytes: 50 * 1024 * 1024,
      shouldCapture: (url) => !url.contains('/analytics'),
    ),
  );
}
