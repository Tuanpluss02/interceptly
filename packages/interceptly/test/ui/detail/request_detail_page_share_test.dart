// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';

class _FakeScopeController extends InterceptlyScopeController {
  _FakeScopeController({required this.record, required super.engine});

  final RequestRecord record;

  @override
  Future<RequestRecord> loadDetail(RequestSummary summary) async => record;

  @override
  Future<RequestRecord> loadDetailById(String id) async => record;
}

IndexEntry _buildEntry(String id, {required String method}) {
  return IndexEntry(
    id: id,
    method: method,
    url: method == 'WS'
        ? 'wss://realtime.example.com/socket'
        : 'https://api.example.com/items/$id',
    statusCode: method == 'WS' ? 101 : 200,
    durationMs: 45,
    requestSizeBytes: 128,
    responseSizeBytes: 256,
    timestamp: DateTime(2026, 1, 1),
    hasError: false,
    requestTruncation: const BodyTruncation.complete(0),
    responseTruncation: const BodyTruncation.complete(0),
    bodyLocation: BodyLocation.memory,
  );
}

void main() {
  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('RequestDetailPage Share Button Visibility', () {
    testWidgets('shows Share FAB for HTTP REST request', (tester) async {
      final entry = _buildEntry('http_1', method: 'GET');
      final record = RequestRecord(
        id: 'http_1',
        method: 'GET',
        url: 'https://api.example.com/items/http_1',
        statusCode: 200,
        durationMs: 45,
        requestSizeBytes: 50,
        responseSizeBytes: 120,
        timestamp: DateTime(2026, 1, 1),
        requestHeaders: const {'content-type': 'application/json'},
        responseHeaders: const {'content-type': 'application/json'},
        requestContentType: 'application/json',
        responseContentType: 'application/json',
        requestBodyPreview: '{"name":"test"}',
        responseBodyPreview: '{"id":"http_1"}',
      );

      final engine = InterceptlyEngine();
      final controller = _FakeScopeController(record: record, engine: engine);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: RequestDetailPage(entry: entry),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('hides Share FAB for Realtime/WebSocket connection',
        (tester) async {
      final entry = _buildEntry('ws_1', method: 'WS');
      final record = RequestRecord(
        id: 'ws_1',
        method: 'WS',
        url: 'wss://realtime.example.com/socket',
        statusCode: 101,
        durationMs: 1200,
        requestSizeBytes: 0,
        responseSizeBytes: 0,
        timestamp: DateTime(2026, 1, 1),
        requestHeaders: const {'upgrade': 'websocket'},
        responseHeaders: const {'upgrade': 'websocket'},
        requestContentType: null,
        responseContentType: null,
        requestBodyPreview: null,
        responseBodyPreview: null,
      );

      final engine = InterceptlyEngine();
      final controller = _FakeScopeController(record: record, engine: engine);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterceptlyScope(
              controller: controller,
              child: RequestDetailPage(entry: entry),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Share'), findsNothing);
    });
  });
}
