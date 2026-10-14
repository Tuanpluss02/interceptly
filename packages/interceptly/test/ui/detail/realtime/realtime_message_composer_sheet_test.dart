import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/detail/realtime/realtime_message_composer_sheet.dart';

void main() {
  group('RealtimeMessageComposerSheet Widget Tests', () {
    testWidgets('Renders WebSocket composer with initial payload and without event input', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RealtimeMessageComposerSheet(
              protocolType: RealtimeProtocolType.webSocket,
              initialPayload: '{"hello":"world"}',
              onSend: (draft) async {},
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('realtime_composer_sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('realtime_composer_event_input')), findsNothing);
      expect(find.byKey(const ValueKey('realtime_composer_payload_input')), findsOneWidget);
      expect(find.text('{"hello":"world"}'), findsOneWidget);
    });

    testWidgets('Renders Socket.IO composer with event input', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RealtimeMessageComposerSheet(
              protocolType: RealtimeProtocolType.socketIo,
              initialEvent: 'chat_event',
              initialPayload: '{"msg":"test"}',
              onSend: (draft) async {},
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('realtime_composer_event_input')), findsOneWidget);
      expect(find.text('chat_event'), findsOneWidget);
      expect(find.byKey(const ValueKey('realtime_composer_payload_input')), findsOneWidget);
    });

    testWidgets('Format JSON button reformats valid minified JSON', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RealtimeMessageComposerSheet(
              protocolType: RealtimeProtocolType.webSocket,
              initialPayload: '{"a":1,"b":[2,3]}',
              onSend: (draft) async {},
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('realtime_composer_format_button')));
      await tester.pump();

      final payloadInput = tester.widget<TextField>(find.byKey(const ValueKey('realtime_composer_payload_input')));
      expect(payloadInput.controller?.text, contains('  "a": 1'));
      expect(payloadInput.controller?.text, contains('  "b": ['));
    });

    testWidgets('Format JSON button with invalid JSON shows inline warning', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RealtimeMessageComposerSheet(
              protocolType: RealtimeProtocolType.webSocket,
              initialPayload: '{invalid-json',
              onSend: (draft) async {},
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('realtime_composer_format_button')));
      await tester.pump();

      expect(find.textContaining('Invalid JSON'), findsOneWidget);
    });

    testWidgets('Tapping send calls onSend and pops Navigator', (tester) async {
      RealtimeMessageDraft? sentDraft;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => RealtimeMessageComposerSheet(
                        protocolType: RealtimeProtocolType.socketIo,
                        initialEvent: 'alert',
                        initialPayload: '{"type":"warning"}',
                        onSend: (draft) async {
                          sentDraft = draft;
                        },
                      ),
                    );
                  },
                  child: const Text('Open Sheet'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('realtime_composer_sheet')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('realtime_composer_send_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('realtime_composer_sheet')), findsNothing);
      expect(sentDraft, isNotNull);
      expect(sentDraft?.event, 'alert');
      expect(sentDraft?.payload, '{"type":"warning"}');
    });

    testWidgets('Tapping cancel pops Navigator without sending', (tester) async {
      bool sent = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => RealtimeMessageComposerSheet(
                        protocolType: RealtimeProtocolType.webSocket,
                        initialPayload: 'hello',
                        onSend: (draft) async {
                          sent = true;
                        },
                      ),
                    );
                  },
                  child: const Text('Open Sheet'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('realtime_composer_sheet')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('realtime_composer_cancel_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('realtime_composer_sheet')), findsNothing);
      expect(sent, isFalse);
    });
  });
}
