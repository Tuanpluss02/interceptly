import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/model/domain_group.dart';
import 'package:interceptly/src/session/inspector_preferences.dart';
import 'package:interceptly/src/ui/detail/detail_tabs_builder.dart';
import 'package:interceptly/src/ui/detail/realtime_messages_tab.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';

class _MockSession extends ChangeNotifier implements InspectorSessionView {
  final Map<String, List<RealtimeFrame>> framesBySession = {};
  final InspectorPreferences _prefs = InspectorPreferences();

  @override
  InterceptlySettings get settings => const InterceptlySettings();

  @override
  InspectorPreferences get preferences => _prefs;

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

  @override
  Future<RequestRecord> loadDetailById(String id) =>
      throw UnimplementedError();

  @override
  Future<RequestRecord> loadDetail(RequestSummary summary) =>
      throw UnimplementedError();

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
      final searchField = find.byType(TextField);
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

    testWidgets('DetailTabsBuilder.buildMessagesTab integrates RealtimeMessagesTab seamlessly',
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

      final builder = DetailTabsBuilder(
        record: record,
        matches: const [],
        activeGlobalIndex: null,
        query: '',
        urlDecodeEnabled: false,
        tryParseJson: (_) => null,
        session: session,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: builder.buildMessagesTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RealtimeMessagesTab), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_card_ws-frame-1')), findsOneWidget);
      expect(find.textContaining('connected'), findsOneWidget);
    });
  });
}
