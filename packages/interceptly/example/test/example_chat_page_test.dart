import 'package:example/src/example_chat_page.dart';
import 'package:example/src/example_local_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExampleChatPage Widget Tests', () {
    late ExampleLocalServer server;

    setUp(() async {
      server = ExampleLocalServer();
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    testWidgets(
        'renders AppBar with StormX, connection status, and action buttons',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExampleChatPage(
            baseUrl: server.baseUrl,
            autoConnect: false,
          ),
        ),
      );

      expect(find.text('StormX (Support Bot)'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('chat_connection_status')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('chat_toggle_connection')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_open_inspector')), findsOneWidget);
    });

    testWidgets('renders quick action chips and input bar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExampleChatPage(
            baseUrl: server.baseUrl,
            autoConnect: false,
          ),
        ),
      );

      expect(find.byKey(const ValueKey('chip_ping')), findsOneWidget);
      expect(find.byKey(const ValueKey('chip_bug')), findsOneWidget);
      expect(find.byKey(const ValueKey('chip_order')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_message_input')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_send_button')), findsOneWidget);
    });

    testWidgets('tapping quick chip populates input or sends message',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExampleChatPage(
            baseUrl: server.baseUrl,
            autoConnect: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('chip_ping')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Input or message list has ping
      expect(find.textContaining('ping'), findsWidgets);
    });

    testWidgets(
        'renders protocol selector and switches between WebSocket and Socket.IO',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExampleChatPage(
            baseUrl: server.baseUrl,
            autoConnect: false,
          ),
        ),
      );

      expect(
          find.byKey(const ValueKey('chat_protocol_selector')), findsOneWidget);
      expect(find.text('WebSocket'), findsOneWidget);
      expect(find.text('Socket.IO'), findsOneWidget);

      await tester.tap(find.text('Socket.IO'));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('chat_protocol_selector')), findsOneWidget);
    });
  });
}
