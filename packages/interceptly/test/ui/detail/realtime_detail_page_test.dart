// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/ui/detail/realtime_detail_page.dart';
import 'package:interceptly/src/ui/detail/realtime_messages_tab.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';

class _FakeRealtimeScopeController extends InterceptlyScopeController {
  _FakeRealtimeScopeController({
    required this.record,
    required this.entry,
    this.frameCounts = const RealtimeFrameCounts(incoming: 8, outgoing: 3),
    required super.engine,
  });

  final RequestRecord record;
  final IndexEntry entry;
  final RealtimeFrameCounts frameCounts;

  @override
  RequestSummary? byId(String id) => entry.id == id ? entry : null;

  @override
  Future<RequestRecord> loadDetail(RequestSummary summary) async => record;

  @override
  Future<RequestRecord> loadDetailById(String id) async => record;

  @override
  RealtimeFrameCounts getRealtimeFrameCounts(String sessionId) => frameCounts;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  IndexEntry createEntry({
    required String id,
    int statusCode = 0,
    int durationMs = 0,
    bool hasError = false,
    String? errorType,
    String? errorMessage,
    DateTime? timestamp,
  }) {
    return IndexEntry(
      id: id,
      method: 'WS',
      url: 'wss://example.com/ws/chat',
      statusCode: statusCode,
      durationMs: durationMs,
      requestSizeBytes: 0,
      responseSizeBytes: 0,
      timestamp: timestamp ?? DateTime(2026, 1, 1, 10, 0, 0),
      hasError: hasError,
      errorType: errorType,
      errorMessage: errorMessage,
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: const BodyTruncation.complete(0),
      bodyLocation: BodyLocation.memory,
      requestHeaders: const {
        'Upgrade': 'websocket',
        'Connection': 'Upgrade',
        'Sec-WebSocket-Version': '13',
      },
    );
  }

  RequestRecord createRecord(IndexEntry entry) {
    return RequestRecord(
      id: entry.id,
      method: entry.method,
      url: entry.url,
      statusCode: entry.statusCode,
      durationMs: entry.durationMs,
      requestSizeBytes: 0,
      responseSizeBytes: 0,
      timestamp: entry.timestamp,
      errorType: entry.errorType,
      errorMessage: entry.errorMessage,
      requestHeaders: entry.requestHeaders,
      responseHeaders: const {},
    );
  }

  testWidgets(
      'RealtimeDetailPage defaults to Messages tab and has no Replay button',
      (tester) async {
    final entry = createEntry(id: 'ws-1');
    final record = createRecord(entry);
    final engine = InterceptlyEngine();
    addTearDown(engine.dispose);
    final controller = _FakeRealtimeScopeController(
      record: record,
      entry: entry,
      engine: engine,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InterceptlyScope(
          controller: controller,
          child: RealtimeDetailPage(
            entry: entry,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify RealtimeMessagesTab is rendered
    expect(find.byType(RealtimeMessagesTab), findsOneWidget);

    // Verify NO Replay chip or button in AppBar
    expect(find.text('Replay'), findsNothing);
    expect(find.byIcon(Icons.replay), findsNothing);

    // Verify Status chip is CONNECTED
    expect(find.text('CONNECTED'), findsOneWidget);
  });

  testWidgets(
      'RealtimeDetailPage switches to Overview tab and displays connection details',
      (tester) async {
    final entry = createEntry(id: 'ws-overview');
    final record = createRecord(entry);
    final engine = InterceptlyEngine();
    addTearDown(engine.dispose);
    final controller = _FakeRealtimeScopeController(
      record: record,
      entry: entry,
      frameCounts: const RealtimeFrameCounts(incoming: 12, outgoing: 5),
      engine: engine,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InterceptlyScope(
          controller: controller,
          child: RealtimeDetailPage(
            entry: entry,
            nowProvider: () => entry.timestamp.add(const Duration(seconds: 45)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Overview tab
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();

    // Verify connection overview items
    expect(find.text('wss://example.com/ws/chat'), findsOneWidget);
    expect(find.text('WS'), findsOneWidget);
    expect(find.text('CONNECTED (Open)'), findsOneWidget);
    expect(find.text('45s'), findsOneWidget);
    expect(find.text('↓ 12 received, ↑ 5 sent (17 total)'), findsOneWidget);

    // Verify handshake headers
    expect(find.text('Sec-WebSocket-Version'), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
    expect(find.text('websocket'), findsOneWidget);
  });

  testWidgets('RealtimeDetailPage live ticker advances duration every second',
      (tester) async {
    var currentTime = DateTime(2026, 1, 1, 10, 0, 0);
    final entry = createEntry(id: 'ws-ticker', timestamp: currentTime);
    final record = createRecord(entry);
    final engine = InterceptlyEngine();
    addTearDown(engine.dispose);
    final controller = _FakeRealtimeScopeController(
      record: record,
      entry: entry,
      engine: engine,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InterceptlyScope(
          controller: controller,
          child: RealtimeDetailPage(
            entry: entry,
            nowProvider: () => currentTime,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Overview tab to view duration
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();

    expect(find.text('0ms'), findsOneWidget);

    // Advance 5 seconds and pump ticker
    currentTime = currentTime.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('5s'), findsOneWidget);
  });

  testWidgets(
      'RealtimeDetailPage renders CLOSED and DROPPED badges appropriately',
      (tester) async {
    final closedEntry = createEntry(id: 'ws-closed', statusCode: 1000);
    final closedRecord = createRecord(closedEntry);
    final closedEngine = InterceptlyEngine();
    addTearDown(closedEngine.dispose);
    final closedController = _FakeRealtimeScopeController(
      record: closedRecord,
      entry: closedEntry,
      engine: closedEngine,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InterceptlyScope(
          controller: closedController,
          child: RealtimeDetailPage(
            entry: closedEntry,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CLOSED'), findsOneWidget);

    final droppedEntry = createEntry(
      id: 'ws-dropped',
      statusCode: 1006,
      hasError: true,
      errorType: 'WebSocketException',
      errorMessage: 'Abnormal closure',
    );
    final droppedRecord = createRecord(droppedEntry);
    final droppedEngine = InterceptlyEngine();
    addTearDown(droppedEngine.dispose);
    final droppedController = _FakeRealtimeScopeController(
      record: droppedRecord,
      entry: droppedEntry,
      engine: droppedEngine,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InterceptlyScope(
          controller: droppedController,
          child: RealtimeDetailPage(
            entry: droppedEntry,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DROPPED'), findsOneWidget);
  });
}
