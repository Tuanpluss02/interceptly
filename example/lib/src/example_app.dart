import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';

import 'example_clients.dart';
import 'example_home_page.dart';

class InterceptlyExampleApp extends StatelessWidget {
  const InterceptlyExampleApp({
    super.key,
    required this.clients,
    required this.navigatorKey,
  });

  final ExampleClients clients;
  final GlobalKey<NavigatorState> navigatorKey;

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
      builder: (context, child) {
        InterceptlyTheme.bind(context: context, themeMode: ThemeMode.system);
        return child ?? const SizedBox.shrink();
      },
      home: InterceptlyOverlay(
        navigatorKey: navigatorKey,
        child: ExampleHomePage(
          dio: clients.dio,
          httpClient: clients.httpClient,
          chopperClient: clients.chopperClient,
        ),
      ),
    );
  }
}
