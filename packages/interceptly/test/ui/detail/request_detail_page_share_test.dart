import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/domain_group.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/session/inspector_preferences.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';

class _FakeSession extends InspectorSessionView {
  _FakeSession({required this.record, required this.entry});

  final RequestRecord record;
  final IndexEntry entry;
  final InspectorPreferences _prefs = InspectorPreferences();

  @override
  InterceptlySettings get settings => const InterceptlySettings();
  @override
  InspectorPreferences get preferences => _prefs;
  @override
  List<RequestSummary> get entries => [entry];
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
  Future<RequestRecord> loadDetail(RequestSummary summary) async => record;
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
  bool get isRealtimeActive => false;
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

      final session = _FakeSession(record: record, entry: entry);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestDetailPage(entry: entry, session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('hides Share FAB for Realtime/WebSocket connection', (tester) async {
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

      final session = _FakeSession(record: record, entry: entry);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestDetailPage(entry: entry, session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Share'), findsNothing);
    });
  });
}
