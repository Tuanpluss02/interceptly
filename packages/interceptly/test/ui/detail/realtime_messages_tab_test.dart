import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/model/domain_group.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/session/inspector_preferences.dart';
import 'package:interceptly/src/ui/detail/realtime/bounded_lru_cache.dart';
import 'package:interceptly/src/ui/detail/realtime/realtime_filter_header.dart';
import 'package:interceptly/src/ui/detail/realtime/realtime_payload_view.dart';
import 'package:interceptly/src/ui/detail/realtime_detail_page.dart';
import 'package:interceptly/src/ui/detail/realtime_messages_tab.dart';
import 'package:interceptly/src/ui/tabs/network_tab.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';

class _MockSession extends ChangeNotifier implements InspectorSessionView {
  final Map<String, List<RealtimeFrame>> framesBySession = {};
  final InspectorPreferences _prefs = InspectorPreferences();

  @override
  InterceptlySettings get settings => const InterceptlySettings();

  @override
  InspectorPreferences get preferences => _prefs;

  @override
  bool get isRealtimeActive => false;

  @override
  List<RequestSummary> get entries => const [];

  @override
  int get entriesVersion => 0;

  @override
  RequestFilter get filter => RequestFilter();

  @override
  bool get isEnabled => true;

  @override
  int get droppedCount => 0;

  @override
  NetworkSimulationProfile get networkSimulation =>
      NetworkSimulationProfile.none;

  @override
  String? get masterQuery => null;

  @override
  bool get isMasterSearchActive => false;

  @override
  bool get isScanningBodies => false;

  @override
  bool get isScanningFiles => false;

  @override
  bool get groupingEnabled => false;

  @override
  Set<SearchMatchScope> getSearchScopes(String id) => const {};

  @override
  RequestSummary? byId(String id) => null;

  RequestRecord? recordToReturn;

  @override
  Future<RequestRecord> loadDetailById(String id) async =>
      recordToReturn ?? (throw UnimplementedError());

  @override
  Future<RequestRecord> loadDetail(RequestSummary summary) async =>
      recordToReturn ?? (throw UnimplementedError());

  @override
  void enable() {}

  @override
  void disable() {}

  @override
  Future<void> clear() async {}

  @override
  void applyFilter(RequestFilter filter) {}

  @override
  void clearFilter() {}

  @override
  void setNetworkSimulation(NetworkSimulationProfile profile) {}

  @override
  void clearNetworkSimulation() {}

  @override
  List<DomainGroup> getGroupedRecords() => const [];

  @override
  void toggleGrouping(bool enabled) {}

  @override
  void toggleDomainExpanded(String domain) {}

  @override
  void cancelMasterSearch() {}

  @override
  Future<void> startMasterSearch(String query) async {}

  @override
  Set<String> get availableDomains => const {};

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
    InspectorSessionView? session,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: RealtimeMessagesTab(
          sessionId: sessionId,
          session: session,
        ),
      ),
    );
  }

  group('RealtimeMessagesTab', () {
    testWidgets('shows empty state when no frames are captured', (tester) async {
      final session = _MockSession();

      await tester.pumpWidget(
        buildTestWidget(sessionId: 'ws-1', session: session),
      );
      await tester.pumpAndSettle();

      expect(find.text('No WebSocket messages captured.'), findsOneWidget);
    });

    testWidgets('renders incoming and outgoing frames with badges and timestamps',
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

      // Empty state should not be visible
      expect(find.text('No WebSocket messages captured.'), findsNothing);

      // Frame cards
      expect(find.byKey(const ValueKey('frame_card_f-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_f-2')), findsOneWidget);

      // Direction badges
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

      // Timestamps in HH:mm:ss.SSS format
      expect(find.text('14:30:15.123'), findsOneWidget);
      expect(find.text('14:30:16.456'), findsOneWidget);

      // Frame type badges
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

      // Size badges
      expect(find.byKey(const ValueKey('frame_size_f-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_size_f-2')), findsOneWidget);

      // Payload previews
      expect(find.textContaining('hello server'), findsWidgets);
      expect(find.textContaining('hello client'), findsWidgets);

      // Copy buttons exist
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

      // Dynamically add a second frame
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

      // All 3 initially rendered
      expect(find.byKey(const ValueKey('frame_card_f-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_f-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_f-3')), findsOneWidget);

      // 1. Filter by search query
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

      // Clear search query
      await tester.enterText(searchField, '');
      await tester.pumpAndSettle();

      // 2. Filter by direction chip: tap '↑ OUT'
      await tester.tap(find.byKey(const ValueKey('chip_outgoing')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('frame_card_f-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_f-1')), findsNothing);
      expect(find.byKey(const ValueKey('frame_card_f-3')), findsNothing);

      // 3. Filter by type chip: tap 'Binary'
      await tester.tap(find.byKey(const ValueKey('chip_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chip_binary')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('frame_card_f-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_f-1')), findsNothing);
      expect(find.byKey(const ValueKey('frame_card_f-2')), findsNothing);

      // Reset to all
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

      // Search for target keyword present only in offloadedMatching.shortPreview
      final searchField = find.descendant(
        of: find.byType(RealtimeFilterHeader),
        matching: find.byType(TextField),
      );
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'target_preview_keyword');
      await tester.pumpAndSettle();

      // Only matching offloaded frame is visible
      expect(find.byKey(const ValueKey('frame_card_frame_offload_match')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_frame_offload_other')),
          findsNothing);

      // loadRealtimePayload was NOT triggered merely by searching
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

      // Tap copy button
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

      // Before tapping, JsonViewer is not shown
      expect(find.byType(JsonViewer), findsNothing);

      // Tap on the payload preview area to inspect
      await tester.tap(find.byKey(const ValueKey('frame_payload_f-inspect')));
      await tester.pumpAndSettle();

      // Now JsonViewer is mounted for deep inspection
      expect(find.byType(JsonViewer), findsOneWidget);

      // Tap collapse button to collapse back to preview
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
          home: RealtimeDetailPage(
            entry: entry,
            session: session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RealtimeMessagesTab), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_ws-frame-1')), findsOneWidget);
      expect(find.textContaining('connected'), findsOneWidget);
    });

    group('Realtime Message Sender Integration', () {
      testWidgets('renders RealtimeChatBar at bottom of tab even when frames list is empty or populated', (tester) async {
        final session = _MockSession();
        session.activeCanSend = true;
        session.protocol = RealtimeProtocolType.webSocket;

        await tester.pumpWidget(buildTestWidget(sessionId: 'sess_1', session: session));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('realtime_chat_input')), findsOneWidget);
        expect(find.byKey(const ValueKey('realtime_chat_send_button')), findsOneWidget);
      });

      testWidgets('frame cards render Resend and Edit buttons and optional event badge', (tester) async {
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

        await tester.pumpWidget(buildTestWidget(sessionId: 'sess_1', session: session));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('frame_event_frame_sio_1')), findsOneWidget);
        expect(find.text('chat_msg'), findsOneWidget);
        expect(find.byKey(const ValueKey('frame_resend_frame_sio_1')), findsOneWidget);
        expect(find.byKey(const ValueKey('frame_edit_frame_sio_1')), findsOneWidget);
      });

      testWidgets('tapping Edit populates RealtimeChatBar inputs', (tester) async {
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

        await tester.pumpWidget(buildTestWidget(sessionId: 'sess_1', session: session));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('frame_edit_frame_edit_target')));
        await tester.pumpAndSettle();

        final input = tester.widget<TextField>(find.byKey(const ValueKey('realtime_chat_input')));
        expect(input.controller?.text, '{"action":"authenticate"}');

        final eventInput = tester.widget<TextField>(find.byKey(const ValueKey('realtime_chat_event_input')));
        expect(eventInput.controller?.text, 'auth');
      });

      testWidgets('tapping Resend immediately sends frame draft', (tester) async {
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

        await tester.pumpWidget(buildTestWidget(sessionId: 'sess_1', session: session));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('frame_resend_frame_resend_target')));
        await tester.pumpAndSettle();

        expect(session.sentDrafts.length, 1);
        expect(session.sentDrafts.first.event, 'ping');
        expect(session.sentDrafts.first.payload, '{"action":"heartbeat"}');
      });

      testWidgets('typing and tapping send in chat bar sends message', (tester) async {
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

        await tester.pumpWidget(buildTestWidget(sessionId: 'sess_1', session: session));
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const ValueKey('realtime_chat_input')), 'hello server');
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('realtime_chat_send_button')));
        await tester.pumpAndSettle();

        expect(session.sentDrafts.length, 1);
        expect(session.sentDrafts.first.payload, 'hello server');
      });
    });

    group('Auto-scroll & Scroll-to-bottom Behavior', () {
      testWidgets('auto-scrolls to bottom when new frame arrives and user is near bottom', (tester) async {
        final session = _MockSession();
        for (var i = 0; i < 3; i++) {
          session.addFrame(
            RealtimeFrame.text(
              id: 'frame_$i',
              sessionId: 'sess_scroll',
              timestamp: DateTime(2026, 1, 1, 10, i),
              direction: i.isEven ? FrameDirection.incoming : FrameDirection.outgoing,
              text: 'Message $i initial text',
            ),
          );
        }

        await tester.pumpWidget(buildTestWidget(sessionId: 'sess_scroll', session: session));
        await tester.pumpAndSettle();

        // Initially frame_2 is in view
        expect(find.byKey(const ValueKey('frame_card_frame_2')), findsOneWidget);

        // Add 15 more frames so it extends downwards and auto-scrolls
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

        // The latest frame_17 should be in view at bottom
        expect(find.byKey(const ValueKey('frame_card_frame_17')), findsOneWidget);
        expect(find.byKey(const ValueKey('realtime_jump_to_bottom')), findsNothing);
      });

      testWidgets('shows jump to bottom button when scrolled up, and tapping it scrolls down', (tester) async {
        final session = _MockSession();
        for (var i = 0; i < 20; i++) {
          session.addFrame(
            RealtimeFrame.text(
              id: 'frame_$i',
              sessionId: 'sess_scroll_btn',
              timestamp: DateTime(2026, 1, 1, 10, i),
              direction: i.isEven ? FrameDirection.incoming : FrameDirection.outgoing,
              text: 'Message $i content line',
            ),
          );
        }

        await tester.pumpWidget(buildTestWidget(sessionId: 'sess_scroll_btn', session: session));
        await tester.pumpAndSettle();

        // Drag up to scroll to bottom
        await tester.drag(find.byType(ListView), const Offset(0, -1500));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('frame_card_frame_19')), findsOneWidget);

        // Drag down to scroll up away from bottom
        await tester.drag(find.byType(ListView), const Offset(0, 600));
        await tester.pumpAndSettle();

        // When scrolled up, jump to bottom button appears
        expect(find.byKey(const ValueKey('realtime_jump_to_bottom')), findsOneWidget);

        // Tap jump to bottom
        await tester.tap(find.byKey(const ValueKey('realtime_jump_to_bottom')));
        await tester.pumpAndSettle();

        // Now frame_19 is in view again and jump button disappears
        expect(find.byKey(const ValueKey('frame_card_frame_19')), findsOneWidget);
        expect(find.byKey(const ValueKey('realtime_jump_to_bottom')), findsNothing);
      });

      testWidgets('sending message automatically scrolls to bottom', (tester) async {
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

        await tester.pumpWidget(buildTestWidget(sessionId: 'sess_send_scroll', session: session));
        await tester.pumpAndSettle();

        // Drag up to scroll to bottom
        await tester.drag(find.byType(ListView), const Offset(0, -1500));
        await tester.pumpAndSettle();

        // Drag down to scroll up away from bottom
        await tester.drag(find.byType(ListView), const Offset(0, 600));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('realtime_jump_to_bottom')), findsOneWidget);

        // Send a message
        await tester.enterText(find.byKey(const ValueKey('realtime_chat_input')), 'my new message');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('realtime_chat_send_button')));
        await tester.pumpAndSettle();

        // Should have scrolled to bottom and jump button should disappear
        expect(find.byKey(const ValueKey('realtime_jump_to_bottom')), findsNothing);
      });
    });

    group('Lazy Payload Loading & Short Preview & Isolated Counter', () {
      testWidgets('collapsed card displays shortPreview without reading disk or parsing JSON', (tester) async {
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

        // 1. shortPreview is displayed
        expect(find.text('{"short":"preview only"}'), findsOneWidget);

        // 2. loadRealtimePayload was NOT called
        expect(session.loadPayloadCallCount, equals(0));

        // 3. JsonViewer is NOT mounted
        expect(find.byType(JsonViewer), findsNothing);
      });

      testWidgets('expanding a file-backed card asynchronously fetches and displays payload with loading indicator', (tester) async {
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

        // Tap on payload to inspect
        await tester.tap(find.byKey(const ValueKey('frame_payload_frame_offload_2')));
        await tester.pump(); // Frame scheduled, loading starts

        // Loading indicator should be visible while awaiting
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(session.loadPayloadCallCount, equals(1));

        // Complete the future with full JSON payload
        completer.complete('{"full_data":"loaded from disk asynchronously","count":42}');
        await tester.pumpAndSettle();

        // Loading indicator gone, JsonViewer rendered
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(JsonViewer), findsOneWidget);
        expect(find.textContaining('loaded from disk asynchronously'), findsOneWidget);
      });

      testWidgets('live frame arrivals update only the row counter badge without rebuilding parent NetworkTab list', (tester) async {
        final session = InspectorSession();
        addTearDown(session.dispose);

        session.recordRealtimeConnection(
          id: 'ws_badge_test',
          url: 'wss://socket.example.com/test',
        );

        int buildCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  buildCount++;
                  return NetworkTab(session: session);
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initially 0 IN, 0 OUT
        expect(find.textContaining('↓ 0  ↑ 0'), findsOneWidget);
        final initialBuildCount = buildCount;

        // Record a live frame for this connection
        await session.recordRealtimeFrame(
          RealtimeFrame.memoryText(
            id: 'live_frame_1',
            sessionId: 'ws_badge_test',
            direction: FrameDirection.incoming,
            text: '{"ping":1}',
          ),
        );

        // Pump a frame for ValueListenable to update
        await tester.pump();

        // The counter badge updated to ↓ 1  ↑ 0
        expect(find.textContaining('↓ 1  ↑ 0'), findsOneWidget);

        // The parent widget was NOT rebuilt
        expect(buildCount, equals(initialBuildCount));

        // Drain any throttle timer scheduled by RealtimeStore
        await tester.pump(const Duration(milliseconds: 150));
      });

      testWidgets('late async payload response for recycled RealtimePayloadView is discarded and does not corrupt cache', (tester) async {
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

        // Mount RealtimePayloadView directly with frameA
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return RealtimePayloadView(
                    frame: frameA,
                    isInspected: true,
                    parsedJson: null,
                    session: session,
                    jsonCache: cache,
                    onToggleInspect: () {},
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();
        // Frame A is now loading
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Rebuild with frameB before completerA finishes
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return RealtimePayloadView(
                    frame: frameB,
                    isInspected: true,
                    parsedJson: null,
                    session: session,
                    jsonCache: cache,
                    onToggleInspect: () {},
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();

        // Now frame A completes late
        completerA.complete('{"payload":"late_A"}');
        await tester.pump();

        // Cache must NOT have frame_B mapped to late_A payload
        expect(cache.containsKey('frame_B'), isFalse);

        // Now frame B completes
        completerB.complete('{"payload":"correct_B"}');
        await tester.pumpAndSettle();

        expect(find.textContaining('correct_B'), findsOneWidget);
        expect(cache['frame_B'], equals({'payload': 'correct_B'}));
      });
    });
  });
}
