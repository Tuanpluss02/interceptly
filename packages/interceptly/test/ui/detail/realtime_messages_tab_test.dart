// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/ui/detail/realtime/bounded_lru_cache.dart';
import 'package:interceptly/src/ui/detail/realtime/realtime_filter_header.dart';
import 'package:interceptly/src/ui/detail/realtime/realtime_payload_view.dart';
import 'package:interceptly/src/ui/detail/realtime_detail_page.dart';
import 'package:interceptly/src/ui/detail/realtime_messages_tab.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';
import 'package:interceptly/src/ui/tabs/realtime_list_tab.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';

class _MockSession extends InterceptlyScopeController {
  _MockSession({InterceptlyEngine? engine})
      : super(engine: engine ?? InterceptlyEngine());

  final Map<String, List<RealtimeFrame>> framesBySession = {};
  RequestRecord? recordToReturn;

  @override
  Future<RequestRecord> loadDetailById(String id) async =>
      recordToReturn ?? (throw UnimplementedError());

  @override
  Future<RequestRecord> loadDetail(RequestSummary summary) async =>
      recordToReturn ?? (throw UnimplementedError());

  @override
  List<RealtimeFrame> getRealtimeFrames(String sessionId) =>
      List.unmodifiable(framesBySession[sessionId] ?? const <RealtimeFrame>[]);

  @override
  RealtimeFrameCounts getRealtimeFrameCounts(String sessionId) {
    final frames = framesBySession[sessionId] ?? const <RealtimeFrame>[];
    var incoming = 0;
    var outgoing = 0;
    for (final f in frames) {
      if (f.direction == FrameDirection.incoming) {
        incoming++;
      } else {
        outgoing++;
      }
    }
    return RealtimeFrameCounts(incoming: incoming, outgoing: outgoing);
  }

  bool activeCanSend = false;
  RealtimeProtocolType? protocol;
  final List<RealtimeMessageDraft> sentDrafts = [];

  @override
  bool canSendRealtimeMessage(String sessionId) => activeCanSend;

  @override
  RealtimeProtocolType? getRealtimeProtocol(String sessionId) => protocol;

  int loadPayloadCallCount = 0;
  Future<dynamic> Function(RealtimeFrame frame)? customLoadPayload;

  @override
  ValueListenable<RealtimeFrameCounts> getRealtimeFrameCountsNotifier(
    String sessionId,
  ) =>
      ValueNotifier(getRealtimeFrameCounts(sessionId));

  @override
  Future<dynamic> loadRealtimePayload(RealtimeFrame frame) async {
    loadPayloadCallCount++;
    if (customLoadPayload != null) {
      return customLoadPayload!(frame);
    }
    return frame.textPayload ?? frame.binaryPayload ?? '';
  }

  @override
  Future<void> sendRealtimeMessage(
      String sessionId, RealtimeMessageDraft draft) async {
    sentDrafts.add(draft);
  }

  void addFrame(RealtimeFrame frame) {
    framesBySession.putIfAbsent(frame.sessionId, () => []).add(frame);
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestWidget({
    required String sessionId,
    _MockSession? session,
  }) {
    final effectiveController = session ?? _MockSession();
    return MaterialApp(
      home: Scaffold(
        body: InterceptlyScope(
          controller: effectiveController,
          child: RealtimeMessagesTab(
            sessionId: sessionId,
          ),
        ),
      ),
    );
  }

  group('RealtimeMessagesTab', () {
    testWidgets('shows empty state when no frames are captured',
        (tester) async {
      final session = _MockSession();

      await tester.pumpWidget(
        buildTestWidget(sessionId: 'ws-1', session: session),
      );
      await tester.pumpAndSettle();

      expect(find.text('No WebSocket messages captured.'), findsOneWidget);
    });

    testWidgets(
        'renders incoming and outgoing frames with badges and timestamps',
        (tester) async {
      final session = _MockSession();
      final t1 = DateTime(2026, 10, 13, 14, 30, 15, 123);
      final t2 = DateTime(2026, 10, 13, 14, 30, 16, 456);

      session.addFrame(
        RealtimeFrame.text(
          id: 'f-1',
          sessionId: 'ws-1',
          direction: FrameDirection.incoming,
          text: '{"greeting":"hello server"}',
          timestamp: t1,
        ),
      );
      session.addFrame(
        RealtimeFrame.text(
          id: 'f-2',
          sessionId: 'ws-1',
          direction: FrameDirection.outgoing,
          text: '{"greeting":"hello client"}',
          timestamp: t2,
        ),
      );

      await tester.pumpWidget(
        buildTestWidget(sessionId: 'ws-1', session: session),
      );
      await tester.pumpAndSettle();

      expect(find.text('No WebSocket messages captured.'), findsNothing);

      expect(find.byKey(const ValueKey('frame_card_f-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_f-2')), findsOneWidget);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('frame_direction_f-1')),
          matching: find.text('↓ IN'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('frame_direction_f-2')),
          matching: find.text('↑ OUT'),
        ),
        findsOneWidget,
      );

      expect(find.text('14:30:15.123'), findsOneWidget);
      expect(find.text('14:30:16.456'), findsOneWidget);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('frame_type_f-1')),
          matching: find.text('Text'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('frame_type_f-2')),
          matching: find.text('Text'),
        ),
        findsOneWidget,
      );

      expect(find.byKey(const ValueKey('frame_size_f-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_size_f-2')), findsOneWidget);

      expect(find.textContaining('hello server'), findsWidgets);
      expect(find.textContaining('hello client'), findsWidgets);

      expect(find.byKey(const ValueKey('frame_copy_f-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_copy_f-2')), findsOneWidget);
    });

    testWidgets('updates dynamically when a new frame is added to session',
        (tester) async {
      final session = _MockSession();

      session.addFrame(
        RealtimeFrame.text(
          id: 'f-1',
          sessionId: 'ws-live',
          direction: FrameDirection.incoming,
          text: 'initial message',
        ),
      );

      await tester.pumpWidget(
        buildTestWidget(sessionId: 'ws-live', session: session),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('frame_card_f-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_f-2')), findsNothing);

      session.addFrame(
        RealtimeFrame.text(
          id: 'f-2',
          sessionId: 'ws-live',
          direction: FrameDirection.outgoing,
          text: 'dynamically added message',
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('frame_card_f-2')), findsOneWidget);
      expect(find.textContaining('dynamically added message'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('frame_direction_f-1')),
          matching: find.text('↓ IN'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('frame_direction_f-2')),
          matching: find.text('↑ OUT'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('filters frames by search query and direction/type chips',
        (tester) async {
      final session = _MockSession();

      session.addFrame(
        RealtimeFrame.text(
          id: 'f-1',
          sessionId: 'ws-filter',
          direction: FrameDirection.incoming,
          text: 'alpha search item',
        ),
      );
      session.addFrame(
        RealtimeFrame.text(
          id: 'f-2',
          sessionId: 'ws-filter',
          direction: FrameDirection.outgoing,
          text: 'beta target item',
        ),
      );
      session.addFrame(
        RealtimeFrame.binary(
          id: 'f-3',
          sessionId: 'ws-filter',
          direction: FrameDirection.incoming,
          bytes: Uint8List.fromList([0x01, 0x02, 0x03]),
        ),
      );

      await tester.pumpWidget(
        buildTestWidget(sessionId: 'ws-filter', session: session),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('frame_card_f-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_f-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_f-3')), findsOneWidget);

      final searchField = find.descendant(
        of: find.byType(RealtimeFilterHeader),
        matching: find.byType(TextField),
      );
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'alpha');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('frame_card_f-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_f-2')), findsNothing);
      expect(find.byKey(const ValueKey('frame_card_f-3')), findsNothing);

      await tester.enterText(searchField, '');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('chip_outgoing')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('frame_card_f-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_f-1')), findsNothing);
      expect(find.byKey(const ValueKey('frame_card_f-3')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('chip_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chip_binary')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('frame_card_f-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_f-1')), findsNothing);
      expect(find.byKey(const ValueKey('frame_card_f-2')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('chip_all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('frame_card_f-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_f-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_f-3')), findsOneWidget);
    });

    testWidgets(
        'searching by text in shortPreview of an offloaded frame matches and displays the frame',
        (tester) async {
      final session = _MockSession();

      final offloadedMatching = RealtimeFrame.offloaded(
        id: 'frame_offload_match',
        sessionId: 'sess_search_preview',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        payloadSizeBytes: 8000,
        shortPreview: '{"query":"target_preview_keyword","status":200}',
        fileOffset: 0,
        fileLength: 8000,
        rotationCount: 0,
      );

      final offloadedOther = RealtimeFrame.offloaded(
        id: 'frame_offload_other',
        sessionId: 'sess_search_preview',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        payloadSizeBytes: 8000,
        shortPreview: '{"query":"unrelated_data"}',
        fileOffset: 8000,
        fileLength: 8000,
        rotationCount: 0,
      );

      session.addFrame(offloadedMatching);
      session.addFrame(offloadedOther);

      await tester.pumpWidget(
        buildTestWidget(sessionId: 'sess_search_preview', session: session),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('frame_card_frame_offload_match')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_frame_offload_other')),
          findsOneWidget);

      final searchField = find.descendant(
        of: find.byType(RealtimeFilterHeader),
        matching: find.byType(TextField),
      );
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'target_preview_keyword');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('frame_card_frame_offload_match')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_frame_offload_other')),
          findsNothing);

      expect(session.loadPayloadCallCount, equals(0));
    });

    testWidgets('copies payload to clipboard on copy button tap',
        (tester) async {
      final session = _MockSession();
      final payload = '{"command":"ping","seq":42}';

      String? clipboardData;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardData = (call.arguments as Map)['text'] as String?;
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return {'text': clipboardData};
        }
        return null;
      });

      session.addFrame(
        RealtimeFrame.text(
          id: 'f-copy',
          sessionId: 'ws-copy',
          direction: FrameDirection.outgoing,
          text: payload,
        ),
      );

      await tester.pumpWidget(
        buildTestWidget(sessionId: 'ws-copy', session: session),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('frame_copy_f-copy')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      expect(clipboardData, equals(payload));
    });

    testWidgets('tapping frame payload toggles inspection / JSON view',
        (tester) async {
      final session = _MockSession();
      final jsonPayload = '{"user":{"id":100,"name":"Alice"}}';

      session.addFrame(
        RealtimeFrame.text(
          id: 'f-inspect',
          sessionId: 'ws-inspect',
          direction: FrameDirection.incoming,
          text: jsonPayload,
        ),
      );

      await tester.pumpWidget(
        buildTestWidget(sessionId: 'ws-inspect', session: session),
      );
      await tester.pumpAndSettle();

      expect(find.byType(JsonViewer), findsNothing);

      await tester.tap(find.byKey(const ValueKey('frame_payload_f-inspect')));
      await tester.pumpAndSettle();

      expect(find.byType(JsonViewer), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('frame_collapse_f-inspect')));
      await tester.pumpAndSettle();

      expect(find.byType(JsonViewer), findsNothing);
    });

    testWidgets('RealtimeDetailPage integrates RealtimeMessagesTab seamlessly',
        (tester) async {
      final session = _MockSession();
      session.addFrame(
        RealtimeFrame.text(
          id: 'ws-frame-1',
          sessionId: 'ws-record-1',
          direction: FrameDirection.incoming,
          text: '{"status":"connected"}',
        ),
      );

      final record = RequestRecord(
        id: 'ws-record-1',
        method: 'WS',
        url: 'wss://example.com/socket',
        statusCode: 101,
        durationMs: 50,
        requestSizeBytes: 0,
        responseSizeBytes: 0,
        requestHeaders: const {},
        responseHeaders: const {},
        timestamp: DateTime(2026, 1, 1),
      );
      session.recordToReturn = record;

      final entry = IndexEntry(
        id: 'ws-record-1',
        method: 'WS',
        url: 'wss://example.com/socket',
        statusCode: 101,
        durationMs: 50,
        requestSizeBytes: 0,
        responseSizeBytes: 0,
        requestHeaders: const {},
        responseHeaders: const {},
        timestamp: DateTime(2026, 1, 1),
        hasError: false,
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation.complete(0),
        bodyLocation: BodyLocation.memory,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: InterceptlyScope(
            controller: session,
            child: RealtimeDetailPage(
              entry: entry,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RealtimeMessagesTab), findsOneWidget);
      expect(
          find.byKey(const ValueKey('frame_card_ws-frame-1')), findsOneWidget);
      expect(find.textContaining('connected'), findsOneWidget);
    });

    group('Realtime Message Sender Integration', () {
      testWidgets(
          'renders RealtimeChatBar at bottom of tab even when frames list is empty or populated',
          (tester) async {
        final session = _MockSession();
        session.activeCanSend = true;
        session.protocol = RealtimeProtocolType.webSocket;

        await tester
            .pumpWidget(buildTestWidget(sessionId: 'sess_1', session: session));
        await tester.pumpAndSettle();

        expect(
            find.byKey(const ValueKey('realtime_chat_input')), findsOneWidget);
        expect(find.byKey(const ValueKey('realtime_chat_send_button')),
            findsOneWidget);
      });

      testWidgets(
          'frame cards render Resend and Edit buttons and optional event badge',
          (tester) async {
        final session = _MockSession();
        session.activeCanSend = true;
        session.protocol = RealtimeProtocolType.socketIo;
        session.addFrame(
          RealtimeFrame.text(
            id: 'frame_sio_1',
            sessionId: 'sess_1',
            timestamp: DateTime(2026, 1, 1),
            direction: FrameDirection.outgoing,
            text: '{"ping":1}',
            eventName: 'chat_msg',
          ),
        );

        await tester
            .pumpWidget(buildTestWidget(sessionId: 'sess_1', session: session));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('frame_event_frame_sio_1')),
            findsOneWidget);
        expect(find.text('chat_msg'), findsOneWidget);
        expect(find.byKey(const ValueKey('frame_resend_frame_sio_1')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('frame_edit_frame_sio_1')),
            findsOneWidget);
      });

      testWidgets('tapping Edit populates RealtimeChatBar inputs',
          (tester) async {
        final session = _MockSession();
        session.activeCanSend = true;
        session.protocol = RealtimeProtocolType.socketIo;
        session.addFrame(
          RealtimeFrame.text(
            id: 'frame_edit_target',
            sessionId: 'sess_1',
            timestamp: DateTime(2026, 1, 1),
            direction: FrameDirection.outgoing,
            text: '{"action":"authenticate"}',
            eventName: 'auth',
          ),
        );

        await tester
            .pumpWidget(buildTestWidget(sessionId: 'sess_1', session: session));
        await tester.pumpAndSettle();

        await tester
            .tap(find.byKey(const ValueKey('frame_edit_frame_edit_target')));
        await tester.pumpAndSettle();

        final input = tester.widget<TextField>(
            find.byKey(const ValueKey('realtime_chat_input')));
        expect(input.controller?.text, '{"action":"authenticate"}');

        final eventInput = tester.widget<TextField>(
            find.byKey(const ValueKey('realtime_chat_event_input')));
        expect(eventInput.controller?.text, 'auth');
      });

      testWidgets('tapping Resend immediately sends frame draft',
          (tester) async {
        final session = _MockSession();
        session.activeCanSend = true;
        session.protocol = RealtimeProtocolType.socketIo;
        session.addFrame(
          RealtimeFrame.text(
            id: 'frame_resend_target',
            sessionId: 'sess_1',
            timestamp: DateTime(2026, 1, 1),
            direction: FrameDirection.outgoing,
            text: '{"action":"heartbeat"}',
            eventName: 'ping',
          ),
        );

        await tester
            .pumpWidget(buildTestWidget(sessionId: 'sess_1', session: session));
        await tester.pumpAndSettle();

        await tester.tap(
            find.byKey(const ValueKey('frame_resend_frame_resend_target')));
        await tester.pumpAndSettle();

        expect(session.sentDrafts.length, 1);
        expect(session.sentDrafts.first.event, 'ping');
        expect(session.sentDrafts.first.payload, '{"action":"heartbeat"}');
      });

      testWidgets('typing and tapping send in chat bar sends message',
          (tester) async {
        final session = _MockSession();
        session.activeCanSend = true;
        session.protocol = RealtimeProtocolType.webSocket;
        session.addFrame(
          RealtimeFrame.text(
            id: 'f1',
            sessionId: 'sess_1',
            timestamp: DateTime(2026, 1, 1),
            direction: FrameDirection.incoming,
            text: 'welcome',
          ),
        );

        await tester
            .pumpWidget(buildTestWidget(sessionId: 'sess_1', session: session));
        await tester.pumpAndSettle();

        await tester.enterText(
            find.byKey(const ValueKey('realtime_chat_input')), 'hello server');
        await tester.pump();

        await tester
            .tap(find.byKey(const ValueKey('realtime_chat_send_button')));
        await tester.pumpAndSettle();

        expect(session.sentDrafts.length, 1);
        expect(session.sentDrafts.first.payload, 'hello server');
      });

      testWidgets(
          'tapping expand when chat input is empty opens composer sheet with disabled send button',
          (tester) async {
        final session = _MockSession();
        session.activeCanSend = true;
        session.protocol = RealtimeProtocolType.webSocket;

        await tester
            .pumpWidget(buildTestWidget(sessionId: 'sess_1', session: session));
        await tester.pumpAndSettle();

        await tester
            .tap(find.byKey(const ValueKey('realtime_chat_expand_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('realtime_composer_sheet')),
            findsOneWidget);
        final sendButton = tester.widget<FilledButton>(
            find.byKey(const ValueKey('realtime_composer_send_button')));
        expect(sendButton.onPressed, isNull);
      });
    });

    group('Auto-scroll & Scroll-to-bottom Behavior', () {
      testWidgets(
          'auto-scrolls to bottom when new frame arrives and user is near bottom',
          (tester) async {
        final session = _MockSession();
        for (var i = 0; i < 3; i++) {
          session.addFrame(
            RealtimeFrame.text(
              id: 'frame_$i',
              sessionId: 'sess_scroll',
              timestamp: DateTime(2026, 1, 1, 10, i),
              direction:
                  i.isEven ? FrameDirection.incoming : FrameDirection.outgoing,
              text: 'Message $i initial text',
            ),
          );
        }

        await tester.pumpWidget(
            buildTestWidget(sessionId: 'sess_scroll', session: session));
        await tester.pumpAndSettle();

        expect(
            find.byKey(const ValueKey('frame_card_frame_2')), findsOneWidget);

        for (var i = 3; i < 18; i++) {
          session.addFrame(
            RealtimeFrame.text(
              id: 'frame_$i',
              sessionId: 'sess_scroll',
              timestamp: DateTime(2026, 1, 1, 10, i),
              direction: FrameDirection.incoming,
              text: 'Message $i payload that extends the list downwards',
            ),
          );
        }
        await tester.pumpAndSettle();

        expect(
            find.byKey(const ValueKey('frame_card_frame_17')), findsOneWidget);
        expect(find.byKey(const ValueKey('realtime_jump_to_bottom')),
            findsNothing);
      });

      testWidgets(
          'shows jump to bottom button when scrolled up, and tapping it scrolls down',
          (tester) async {
        final session = _MockSession();
        for (var i = 0; i < 20; i++) {
          session.addFrame(
            RealtimeFrame.text(
              id: 'frame_$i',
              sessionId: 'sess_scroll_btn',
              timestamp: DateTime(2026, 1, 1, 10, i),
              direction:
                  i.isEven ? FrameDirection.incoming : FrameDirection.outgoing,
              text: 'Message $i content line',
            ),
          );
        }

        await tester.pumpWidget(
            buildTestWidget(sessionId: 'sess_scroll_btn', session: session));
        await tester.pumpAndSettle();

        await tester.drag(find.byType(ListView), const Offset(0, -1500));
        await tester.pumpAndSettle();
        expect(
            find.byKey(const ValueKey('frame_card_frame_19')), findsOneWidget);

        await tester.drag(find.byType(ListView), const Offset(0, 600));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('realtime_jump_to_bottom')),
            findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('realtime_jump_to_bottom')));
        await tester.pumpAndSettle();

        expect(
            find.byKey(const ValueKey('frame_card_frame_19')), findsOneWidget);
        expect(find.byKey(const ValueKey('realtime_jump_to_bottom')),
            findsNothing);
      });

      testWidgets('sending message automatically scrolls to bottom',
          (tester) async {
        final session = _MockSession();
        session.activeCanSend = true;
        session.protocol = RealtimeProtocolType.webSocket;
        for (var i = 0; i < 20; i++) {
          session.addFrame(
            RealtimeFrame.text(
              id: 'frame_$i',
              sessionId: 'sess_send_scroll',
              timestamp: DateTime(2026, 1, 1, 10, i),
              direction: FrameDirection.incoming,
              text: 'Message $i content line',
            ),
          );
        }

        await tester.pumpWidget(
            buildTestWidget(sessionId: 'sess_send_scroll', session: session));
        await tester.pumpAndSettle();

        await tester.drag(find.byType(ListView), const Offset(0, -1500));
        await tester.pumpAndSettle();

        await tester.drag(find.byType(ListView), const Offset(0, 600));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('realtime_jump_to_bottom')),
            findsOneWidget);

        await tester.enterText(
            find.byKey(const ValueKey('realtime_chat_input')),
            'my new message');
        await tester.pump();
        await tester
            .tap(find.byKey(const ValueKey('realtime_chat_send_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('realtime_jump_to_bottom')),
            findsNothing);
      });
    });

    group('Lazy Payload Loading & Short Preview & Isolated Counter', () {
      testWidgets(
          'collapsed card displays shortPreview without reading disk or parsing JSON',
          (tester) async {
        final session = _MockSession();
        final frame = RealtimeFrame.offloaded(
          id: 'frame_offload_1',
          sessionId: 'sess_lazy',
          direction: FrameDirection.incoming,
          type: FrameType.text,
          payloadSizeBytes: 5000,
          shortPreview: '{"short":"preview only"}',
          fileOffset: 0,
          fileLength: 5000,
          rotationCount: 0,
        );

        session.addFrame(frame);

        await tester.pumpWidget(
          buildTestWidget(sessionId: 'sess_lazy', session: session),
        );
        await tester.pumpAndSettle();

        expect(find.text('{"short":"preview only"}'), findsOneWidget);

        expect(session.loadPayloadCallCount, equals(0));

        expect(find.byType(JsonViewer), findsNothing);
      });

      testWidgets(
          'expanding a file-backed card asynchronously fetches and displays payload with loading indicator',
          (tester) async {
        final session = _MockSession();
        final completer = Completer<dynamic>();
        session.customLoadPayload = (frame) => completer.future;

        final frame = RealtimeFrame.offloaded(
          id: 'frame_offload_2',
          sessionId: 'sess_async',
          direction: FrameDirection.incoming,
          type: FrameType.text,
          payloadSizeBytes: 10000,
          shortPreview: '{"preview":"lazy"}',
          fileOffset: 0,
          fileLength: 10000,
          rotationCount: 0,
        );

        session.addFrame(frame);

        await tester.pumpWidget(
          buildTestWidget(sessionId: 'sess_async', session: session),
        );
        await tester.pumpAndSettle();

        await tester
            .tap(find.byKey(const ValueKey('frame_payload_frame_offload_2')));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(session.loadPayloadCallCount, equals(1));

        completer.complete(
            '{"full_data":"loaded from disk asynchronously","count":42}');
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(JsonViewer), findsOneWidget);
        expect(find.textContaining('loaded from disk asynchronously'),
            findsOneWidget);
      });

      testWidgets(
          'live frame arrivals update only the row counter badge without rebuilding parent RealtimeListTab',
          (tester) async {
        final engine = InterceptlyEngine();
        addTearDown(engine.dispose);
        final controller = InterceptlyScopeController(engine: engine);
        addTearDown(controller.dispose);

        engine.recordRealtimeConnection(
          id: 'ws_badge_test',
          url: 'wss://socket.example.com/test',
        );

        int buildCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InterceptlyScope(
                controller: controller,
                child: Builder(
                  builder: (context) {
                    buildCount++;
                    return const RealtimeListTab();
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.textContaining('↓ 0  ↑ 0'), findsOneWidget);
        final initialBuildCount = buildCount;

        await engine.recordRealtimeFrame(
          RealtimeFrame.memoryText(
            id: 'live_frame_1',
            sessionId: 'ws_badge_test',
            direction: FrameDirection.incoming,
            text: '{"ping":1}',
          ),
        );

        await tester.pump(const Duration(milliseconds: 100));

        expect(find.textContaining('↓ 1  ↑ 0'), findsOneWidget);

        expect(buildCount, equals(initialBuildCount));

        await tester.pump(const Duration(milliseconds: 50));
      });

      testWidgets(
          'late async payload response for recycled RealtimePayloadView is discarded and does not corrupt cache',
          (tester) async {
        final session = _MockSession();
        final completerA = Completer<dynamic>();
        final completerB = Completer<dynamic>();
        session.customLoadPayload = (frame) {
          if (frame.id == 'frame_A') return completerA.future;
          return completerB.future;
        };

        final frameA = RealtimeFrame.offloaded(
          id: 'frame_A',
          sessionId: 'sess_race',
          direction: FrameDirection.incoming,
          type: FrameType.text,
          payloadSizeBytes: 500,
          shortPreview: 'preview A',
          fileOffset: 0,
          fileLength: 500,
          rotationCount: 0,
        );

        final frameB = RealtimeFrame.offloaded(
          id: 'frame_B',
          sessionId: 'sess_race',
          direction: FrameDirection.incoming,
          type: FrameType.text,
          payloadSizeBytes: 600,
          shortPreview: 'preview B',
          fileOffset: 500,
          fileLength: 600,
          rotationCount: 0,
        );

        final cache = BoundedLruCache<String, dynamic>(capacity: 30);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InterceptlyScope(
                controller: session,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return RealtimePayloadView(
                      frame: frameA,
                      isInspected: true,
                      parsedJson: null,
                      jsonCache: cache,
                      onToggleInspect: () {},
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InterceptlyScope(
                controller: session,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return RealtimePayloadView(
                      frame: frameB,
                      isInspected: true,
                      parsedJson: null,
                      jsonCache: cache,
                      onToggleInspect: () {},
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        completerA.complete('{"payload":"late_A"}');
        await tester.pump();

        expect(cache.containsKey('frame_B'), isFalse);

        completerB.complete('{"payload":"correct_B"}');
        await tester.pumpAndSettle();

        expect(find.textContaining('correct_B'), findsOneWidget);
        expect(cache['frame_B'], equals({'payload': 'correct_B'}));
      });
    });
  });
}
