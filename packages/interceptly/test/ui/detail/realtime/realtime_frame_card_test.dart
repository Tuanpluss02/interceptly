import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/detail/realtime/realtime_frame_card.dart';

void main() {
  group('RealtimeFrameCard Overflow & Layout Tests', () {
    testWidgets(
      'renders cleanly without RenderFlex overflow on narrow mobile screen (360x800)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final frame = RealtimeFrame.text(
          id: 'frame_narrow_1',
          sessionId: 'sess_1',
          timestamp: DateTime(2026, 1, 1, 14, 30, 15, 123),
          direction: FrameDirection.outgoing,
          text: '{"msg":"hello world"}',
          eventName: 'chat_message',
          payloadSizeBytes: 1024,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: RealtimeFrameCard(
                  frame: frame,
                  isInspected: false,
                  parsedJson: {'msg': 'hello world'},
                  onToggleInspect: () {},
                  onCopy: () {},
                  onEdit: () {},
                  onResend: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('frame_card_frame_narrow_1')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('frame_direction_frame_narrow_1')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('frame_type_frame_narrow_1')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('frame_event_frame_narrow_1')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('frame_size_frame_narrow_1')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('frame_time_frame_narrow_1')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('frame_inspect_frame_narrow_1')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('frame_copy_frame_narrow_1')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('frame_edit_frame_narrow_1')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('frame_resend_frame_narrow_1')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders cleanly on ultra-narrow screen (320x568)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final frame = RealtimeFrame.text(
          id: 'frame_320',
          sessionId: 'sess_1',
          timestamp: DateTime(2026, 1, 1, 14, 30, 15, 123),
          direction: FrameDirection.incoming,
          text: '{"status":"ok"}',
          eventName: 'order_status',
          payloadSizeBytes: 256,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: RealtimeFrameCard(
                  frame: frame,
                  isInspected: false,
                  parsedJson: null,
                  onToggleInspect: () {},
                  onCopy: () {},
                  onEdit: () {},
                  onResend: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
            find.byKey(const ValueKey('frame_card_frame_320')), findsOneWidget);
        expect(find.byKey(const ValueKey('frame_event_frame_320')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'handles very long event name without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final frame = RealtimeFrame.text(
          id: 'frame_long_event',
          sessionId: 'sess_1',
          timestamp: DateTime(2026, 1, 1, 14, 30, 15, 123),
          direction: FrameDirection.incoming,
          text: '{"status":"ok"}',
          eventName:
              'extremely_long_event_name_that_would_easily_overflow_any_row',
          payloadSizeBytes: 512,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: RealtimeFrameCard(
                  frame: frame,
                  isInspected: false,
                  parsedJson: null,
                  onToggleInspect: () {},
                  onCopy: () {},
                  onEdit: () {},
                  onResend: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('frame_card_frame_long_event')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('frame_event_frame_long_event')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders cleanly on wide screen (800x600)',
      (tester) async {
        final frame = RealtimeFrame.text(
          id: 'frame_wide',
          sessionId: 'sess_1',
          timestamp: DateTime(2026, 1, 1, 14, 30, 15, 123),
          direction: FrameDirection.outgoing,
          text: '{"ping":true}',
          eventName: 'ping',
          payloadSizeBytes: 64,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RealtimeFrameCard(
                frame: frame,
                isInspected: false,
                parsedJson: null,
                onToggleInspect: () {},
                onCopy: () {},
                onEdit: () {},
                onResend: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('frame_card_frame_wide')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('frame_time_frame_wide')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'triggers action button callbacks when tapped',
      (tester) async {
        bool inspected = false;
        bool copied = false;
        bool edited = false;
        bool resent = false;

        final frame = RealtimeFrame.text(
          id: 'frame_actions',
          sessionId: 'sess_1',
          timestamp: DateTime(2026, 1, 1, 14, 30, 15, 123),
          direction: FrameDirection.outgoing,
          text: '{"action":"test"}',
          eventName: 'test_event',
          payloadSizeBytes: 64,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RealtimeFrameCard(
                frame: frame,
                isInspected: false,
                parsedJson: null,
                onToggleInspect: () => inspected = true,
                onCopy: () => copied = true,
                onEdit: () => edited = true,
                onResend: () => resent = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester
            .tap(find.byKey(const ValueKey('frame_inspect_frame_actions')));
        expect(inspected, isTrue);

        await tester
            .tap(find.byKey(const ValueKey('frame_copy_frame_actions')));
        expect(copied, isTrue);

        await tester
            .tap(find.byKey(const ValueKey('frame_edit_frame_actions')));
        expect(edited, isTrue);

        await tester
            .tap(find.byKey(const ValueKey('frame_resend_frame_actions')));
        expect(resent, isTrue);
      },
    );
  });
}
