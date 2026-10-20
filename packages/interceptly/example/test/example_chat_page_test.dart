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

    testWidgets('renders TabBar with Stock (WebSocket) and Chat (Socket.IO)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExampleChatPage(
              baseUrl: server.baseUrl,
              autoConnect: false,
            ),
          ),
        ),
      );

      expect(find.text('Stock (WebSocket)'), findsOneWidget);
      expect(find.text('Chat (Socket.IO)'), findsOneWidget);
    });

    testWidgets('renders Stock ticker cards and WebSocket controls in Tab 1',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExampleChatPage(
              baseUrl: server.baseUrl,
              autoConnect: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(find.text('Thị trường chứng khoán'), findsOneWidget);
      expect(find.text('VCB'), findsOneWidget);
      expect(find.text('FPT'), findsOneWidget);
      expect(find.text('HPG'), findsOneWidget);
      expect(find.text('MWG'), findsOneWidget);
      expect(find.byKey(const ValueKey('chip_ping_ws')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chip_ping_ws')));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.textContaining('Ping -> WebSocket'), findsWidgets);
    });

    testWidgets(
        'switches to Chat tab and renders StormX header, chat controls and input bar',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExampleChatPage(
              baseUrl: server.baseUrl,
              autoConnect: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // Switch to Chat tab
      await tester.tap(find.text('Chat (Socket.IO)'));
      await tester.pumpAndSettle();

      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('StormX (Support Bot)'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('chat_connection_status')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('chat_toggle_connection')), findsOneWidget);
      expect(find.byKey(const ValueKey('chip_ping')), findsOneWidget);
      expect(find.byKey(const ValueKey('chip_bug')), findsOneWidget);
      expect(find.byKey(const ValueKey('chip_order')), findsOneWidget);
      expect(find.byKey(const ValueKey('chip_binary')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_message_input')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_send_button')), findsOneWidget);

      final textField = tester.widget<TextField>(
        find.byKey(const ValueKey('chat_message_input')),
      );
      expect(textField.decoration?.hintText, equals('Send message'));

      // Tap ping chip
      await tester.tap(find.byKey(const ValueKey('chip_ping')));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.textContaining('ping'), findsWidgets);
    });
  });
}
