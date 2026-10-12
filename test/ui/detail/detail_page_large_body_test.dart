import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/domain_group.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';
import 'package:interceptly/src/model/network_simulation.dart';
import 'package:interceptly/src/model/request_filter.dart';
import 'package:interceptly/src/model/request_record.dart';
import 'package:interceptly/src/model/request_summary.dart';
import 'package:interceptly/src/session/inspector_preferences.dart';
import 'package:interceptly/src/session/inspector_session_view.dart';
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
}

void main() {
  testWidgets('detail page opens large JSON body without throwing',
      (tester) async {
    final items = List.generate(
      4000,
      (i) => {'id': i, 'name': 'item number $i with padding text'},
    );
    final bigJson = jsonEncode({'data': items});
    expect(bigJson.length, greaterThan(100 * 1024));

    final entry = IndexEntry(
      id: 'r1',
      method: 'GET',
      url: 'https://api.example.com/data',
      statusCode: 200,
      durationMs: 12,
      requestSizeBytes: 0,
      responseSizeBytes: bigJson.length,
      timestamp: DateTime.now(),
      hasError: false,
      isBodyTruncated: false,
      bodyLocation: BodyLocation.memory,
    );
    final record = RequestRecord(
      id: 'r1',
      method: 'GET',
      url: 'https://api.example.com/data',
      statusCode: 200,
      durationMs: 12,
      requestSizeBytes: 0,
      responseSizeBytes: bigJson.length,
      timestamp: DateTime.now(),
      requestHeaders: const {},
      responseHeaders: const {'content-type': 'application/json'},
      responseContentType: 'application/json',
      responseBodyPreview: bigJson,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailPage(
          entry: entry,
          session: _FakeSession(record: record, entry: entry),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('URL'), findsOneWidget);

    await tester.tap(find.text('Response'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('RESPONSE BODY'), findsOneWidget);
  });

  testWidgets('detail page opens small JSON body without RangeError',
      (tester) async {
    const smallJson = '{"status":"ok"}';
    final entry = IndexEntry(
      id: 'r2',
      method: 'GET',
      url: 'https://api.example.com/small',
      statusCode: 200,
      durationMs: 12,
      requestSizeBytes: 0,
      responseSizeBytes: smallJson.length,
      timestamp: DateTime.now(),
      hasError: false,
      isBodyTruncated: false,
      bodyLocation: BodyLocation.memory,
    );
    final record = RequestRecord(
      id: 'r2',
      method: 'GET',
      url: 'https://api.example.com/small',
      statusCode: 200,
      durationMs: 12,
      requestSizeBytes: 0,
      responseSizeBytes: smallJson.length,
      timestamp: DateTime.now(),
      requestHeaders: const {},
      responseHeaders: const {'content-type': 'application/json'},
      responseContentType: 'application/json',
      responseBodyPreview: smallJson,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailPage(
          entry: entry,
          session: _FakeSession(record: record, entry: entry),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
