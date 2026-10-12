import 'package:flutter/material.dart';

import 'example_clients.dart';
import 'example_home_page.dart';
import 'example_local_server.dart';

class InterceptlyExampleApp extends StatelessWidget {
  const InterceptlyExampleApp({
    super.key,
    required this.clients,
    required this.navigatorKey,
    required this.server,
  });

  final ExampleClients clients;
  final GlobalKey<NavigatorState> navigatorKey;
  final ExampleLocalServer server;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Interceptly Example',
      themeMode: ThemeMode.system,
      theme: ThemeData.from(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: ExampleHomePage(
        dio: clients.dio,
        httpClient: clients.httpClient,
        chopperClient: clients.chopperClient,
        server: server,
      ),
    );
  }
}
