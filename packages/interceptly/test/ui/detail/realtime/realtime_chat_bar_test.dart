import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/detail/realtime/realtime_chat_bar.dart';

void main() {
  group('RealtimeChatBar Widget Tests', () {
    late TextEditingController textController;
    late TextEditingController eventController;

    setUp(() {
      textController = TextEditingController();
      eventController = TextEditingController();
    });

    tearDown(() {
      textController.dispose();
      eventController.dispose();
    });

    testWidgets(
        'Active WebSocket mode renders payload input without event input',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RealtimeChatBar(
              sessionId: 'ws_test_1',
              canSend: true,
              protocolType: RealtimeProtocolType.webSocket,
              textController: textController,
              eventController: eventController,
              onSend: () {},
              onExpand: () {},
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('realtime_chat_input')), findsOneWidget);
      expect(find.byKey(const ValueKey('realtime_chat_event_input')),
          findsNothing);
      expect(find.byKey(const ValueKey('realtime_chat_send_button')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('realtime_chat_expand_button')),
          findsOneWidget);
    });

    testWidgets('Active Socket.IO mode renders event input and payload input',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RealtimeChatBar(
              sessionId: 'sio_test_1',
              canSend: true,
              protocolType: RealtimeProtocolType.socketIo,
              textController: textController,
              eventController: eventController,
              onSend: () {},
              onExpand: () {},
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('realtime_chat_event_input')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('realtime_chat_input')), findsOneWidget);
      expect(find.byKey(const ValueKey('realtime_chat_send_button')),
          findsOneWidget);
    });

    testWidgets(
        'Closed connection mode renders notice and disables inputs and send button',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RealtimeChatBar(
              sessionId: 'ws_test_closed',
              canSend: false,
              protocolType: RealtimeProtocolType.webSocket,
              textController: textController,
              eventController: eventController,
              onSend: () {},
              onExpand: () {},
            ),
          ),
        ),
      );

      expect(find.text('Connection is closed'), findsOneWidget);

      final textField = tester
          .widget<TextField>(find.byKey(const ValueKey('realtime_chat_input')));
      expect(textField.enabled, isFalse);

      final sendButton = tester.widget<IconButton>(
          find.byKey(const ValueKey('realtime_chat_send_button')));
      expect(sendButton.onPressed, isNull);
    });

    testWidgets('SSE mode renders read-only stream notice', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RealtimeChatBar(
              sessionId: 'sse_test_1',
              canSend: false,
              protocolType: RealtimeProtocolType.sse,
              textController: textController,
              eventController: eventController,
              onSend: () {},
              onExpand: () {},
            ),
          ),
        ),
      );

      expect(find.text('Server-Sent Events is a read-only stream'),
          findsOneWidget);
      final textField = tester
          .widget<TextField>(find.byKey(const ValueKey('realtime_chat_input')));
      expect(textField.enabled, isFalse);
    });

    testWidgets(
        'Typing text enables send button and tapping send triggers callback',
        (tester) async {
      bool sent = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RealtimeChatBar(
              sessionId: 'ws_test_type',
              canSend: true,
              protocolType: RealtimeProtocolType.webSocket,
              textController: textController,
              eventController: eventController,
              onSend: () {
                sent = true;
              },
              onExpand: () {},
            ),
          ),
        ),
      );

      var sendButton = tester.widget<IconButton>(
          find.byKey(const ValueKey('realtime_chat_send_button')));
      expect(sendButton.onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('realtime_chat_input')),
          '{"action":"ping"}');
      await tester.pump();

      sendButton = tester.widget<IconButton>(
          find.byKey(const ValueKey('realtime_chat_send_button')));
      expect(sendButton.onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('realtime_chat_send_button')));
      await tester.pump();

      expect(sent, isTrue);
    });

    testWidgets('Tapping expand button triggers onExpand callback',
        (tester) async {
      bool expanded = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RealtimeChatBar(
              sessionId: 'ws_test_expand',
              canSend: true,
              protocolType: RealtimeProtocolType.webSocket,
              textController: textController,
              eventController: eventController,
              onSend: () {},
              onExpand: () {
                expanded = true;
              },
            ),
          ),
        ),
      );

      await tester
          .tap(find.byKey(const ValueKey('realtime_chat_expand_button')));
      await tester.pump();

      expect(expanded, isTrue);
    });
  });
}
