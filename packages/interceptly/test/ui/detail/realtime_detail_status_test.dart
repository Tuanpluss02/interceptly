// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/ui/detail/realtime_detail_page.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';

class _FakeRealtimeScopeController extends InterceptlyScopeController {
  _FakeRealtimeScopeController({
    required this.record,
    required this.entry,
    this.frameCounts = const RealtimeFrameCounts(incoming: 2, outgoing: 1),
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

  testWidgets(
      'displays CONNECTED badge and overview details for active realtime session',
      (tester) async {
    final entry = IndexEntry(
      id: 'ws-active',
      method: 'WS',
      url: 'wss://example.com/live',
      statusCode: 0,
      durationMs: 0,
      requestSizeBytes: 0,
      responseSizeBytes: 0,
      timestamp: DateTime.now().subtract(const Duration(seconds: 45)),
      hasError: false,
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: const BodyTruncation.complete(0),
      bodyLocation: BodyLocation.memory,
    );

    final record = RequestRecord(
      id: 'ws-active',
      method: 'WS',
      url: 'wss://example.com/live',
      statusCode: 0,
      durationMs: 0,
      requestSizeBytes: 0,
      responseSizeBytes: 0,
      timestamp: entry.timestamp,
      requestHeaders: const {},
      responseHeaders: const {},
    );

    final engine = InterceptlyEngine();
    addTearDown(engine.dispose);
    final controller = _FakeRealtimeScopeController(
      record: record,
      entry: entry,
      frameCounts: const RealtimeFrameCounts(incoming: 8, outgoing: 3),
      engine: engine,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InterceptlyScope(
          controller: controller,
          child: RequestDetailPage(
            entry: entry,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Status chip in AppBar
    expect(find.text('CONNECTED'), findsOneWidget);

    // Switch to Overview tab
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();

    // Overview tab content
    expect(find.text('CONNECTED (Open)'), findsOneWidget);
    expect(
      find.text('↓ 8 received, ↑ 3 sent (11 total)'),
      findsOneWidget,
    );
  });

  testWidgets(
      'displays CLOSED badge and overview for normally closed realtime session',
      (tester) async {
    final entry = IndexEntry(
      id: 'ws-closed',
      method: 'WS',
      url: 'wss://example.com/live',
      statusCode: 1000,
      durationMs: 5000,
      requestSizeBytes: 0,
      responseSizeBytes: 0,
      timestamp: DateTime.now().subtract(const Duration(seconds: 10)),
      hasError: false,
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: const BodyTruncation.complete(0),
      bodyLocation: BodyLocation.memory,
    );

    final record = RequestRecord(
      id: 'ws-closed',
      method: 'WS',
      url: 'wss://example.com/live',
      statusCode: 1000,
      durationMs: 5000,
      requestSizeBytes: 0,
      responseSizeBytes: 0,
      timestamp: entry.timestamp,
      requestHeaders: const {},
      responseHeaders: const {},
    );

    final engine = InterceptlyEngine();
    addTearDown(engine.dispose);
    final controller = _FakeRealtimeScopeController(
      record: record,
      entry: entry,
      frameCounts: const RealtimeFrameCounts(incoming: 10, outgoing: 4),
      engine: engine,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InterceptlyScope(
          controller: controller,
          child: RequestDetailPage(
            entry: entry,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Status chip in AppBar
    expect(find.text('CLOSED'), findsOneWidget);

    // Switch to Overview tab
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();

    // Overview tab content
    expect(find.text('CLOSED (1000)'), findsOneWidget);
  });

  testWidgets(
      'displays DROPPED badge and overview for abnormally closed realtime session',
      (tester) async {
    final entry = IndexEntry(
      id: 'ws-dropped',
      method: 'WS',
      url: 'wss://example.com/live',
      statusCode: 1006,
      durationMs: 12000,
      requestSizeBytes: 0,
      responseSizeBytes: 0,
      timestamp: DateTime.now().subtract(const Duration(seconds: 20)),
      hasError: true,
      errorType: 'WebSocketException',
      errorMessage: 'Connection reset by peer',
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: const BodyTruncation.complete(0),
      bodyLocation: BodyLocation.memory,
    );

    final record = RequestRecord(
      id: 'ws-dropped',
      method: 'WS',
      url: 'wss://example.com/live',
      statusCode: 1006,
      durationMs: 12000,
      requestSizeBytes: 0,
      responseSizeBytes: 0,
      timestamp: entry.timestamp,
      requestHeaders: const {},
      responseHeaders: const {},
      errorType: 'WebSocketException',
      errorMessage: 'Connection reset by peer',
    );

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
          child: RequestDetailPage(
            entry: entry,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Status chip in AppBar
    expect(find.text('DROPPED'), findsOneWidget);

    // Switch to Overview tab
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();

    // Overview tab content
    expect(find.text('DROPPED (1006)'), findsOneWidget);
  });

  testWidgets(
      'live ticker updates duration periodically for active realtime session in detail page',
      (tester) async {
    var currentTime = DateTime(2026, 1, 1, 12, 0, 0);
    final start = currentTime;
    final entry = IndexEntry(
      id: 'ws-ticker-live',
      method: 'WS',
      url: 'wss://example.com/live',
      statusCode: 0,
      durationMs: 0,
      requestSizeBytes: 0,
      responseSizeBytes: 0,
      timestamp: start,
      hasError: false,
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: const BodyTruncation.complete(0),
      bodyLocation: BodyLocation.memory,
    );

    final record = RequestRecord(
      id: 'ws-ticker-live',
      method: 'WS',
      url: 'wss://example.com/live',
      statusCode: 0,
      durationMs: 0,
      requestSizeBytes: 0,
      responseSizeBytes: 0,
      timestamp: start,
      requestHeaders: const {},
      responseHeaders: const {},
    );

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
          child: RequestDetailPage(
            entry: entry,
            nowProvider: () => currentTime,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Overview tab
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();

    expect(find.text('0ms'), findsOneWidget);

    // Advance time by 3 seconds and pump ticker
    currentTime = currentTime.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('3s'), findsOneWidget);

    // Advance time by 62 seconds (total 65s -> 1m 5s)
    currentTime = currentTime.add(const Duration(seconds: 62));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1m 5s'), findsOneWidget);
  });

  testWidgets(
      'RequestDetailPage forwards realtime entries to RealtimeDetailPage',
      (tester) async {
    final entry = IndexEntry(
      id: 'ws-compat',
      method: 'WS',
      url: 'wss://example.com/live',
      statusCode: 0,
      durationMs: 0,
      requestSizeBytes: 0,
      responseSizeBytes: 0,
      timestamp: DateTime.now(),
      hasError: false,
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: const BodyTruncation.complete(0),
      bodyLocation: BodyLocation.memory,
    );
    final record = RequestRecord(
      id: 'ws-compat',
      method: 'WS',
      url: 'wss://example.com/live',
      statusCode: 0,
      durationMs: 0,
      requestSizeBytes: 0,
      responseSizeBytes: 0,
      timestamp: entry.timestamp,
      requestHeaders: const {},
      responseHeaders: const {},
    );
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
          child: RequestDetailPage(
            entry: entry,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RealtimeDetailPage), findsOneWidget);
    expect(find.text('Replay'), findsNothing);
  });
}
