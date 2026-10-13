import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/body_truncation.dart';
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

class _StubSession extends InspectorSessionView {
  _StubSession(this.record);

  final RequestRecord record;
  final InspectorPreferences _prefs = InspectorPreferences();

  @override
  InterceptlySettings get settings => const InterceptlySettings();

  @override
  InspectorPreferences get preferences => _prefs;

  @override
  List<RequestSummary> get entries => const [];

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
  testWidgets(
      'preview-truncated body renders the preview instead of the full bytes',
      (tester) async {
    final previewText = jsonEncode({
      'items': [1, 2, 3],
      'marker': 'ZZPREVIEWZZ'
    });
    final fullText = jsonEncode({
      'items': List.generate(3000, (i) => 'value-$i'),
      'marker': 'ZZFULLZZ',
    });
    final fullBytes = Uint8List.fromList(utf8.encode(fullText));

    final record = RequestRecord(
      id: 'rec_preview_cut',
      method: 'GET',
      url: 'https://api.example.com/heavy',
      statusCode: 200,
      timestamp: DateTime(2026),
      durationMs: 10,
      requestSizeBytes: 0,
      responseSizeBytes: fullBytes.length,
      requestHeaders: const {},
      responseHeaders: const {'content-type': 'application/json'},
      responseContentType: 'application/json',
      responseBodyPreview: previewText,
      responseBodyBytes: fullBytes,
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: const BodyTruncation(
        originalBytes: 500000,
        retainedBytes: 40,
        stage: TruncationStage.preview,
      ),
    );

    final entry = IndexEntry(
      id: record.id,
      method: record.method,
      url: record.url,
      statusCode: record.statusCode,
      durationMs: record.durationMs,
      requestSizeBytes: 0,
      responseSizeBytes: record.responseSizeBytes,
      timestamp: record.timestamp,
      hasError: false,
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: record.responseTruncation,
      bodyLocation: BodyLocation.memory,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailPage(entry: entry, session: _StubSession(record)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Response'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing is lost'), findsOneWidget);
    expect(find.textContaining('ZZPREVIEWZZ'), findsOneWidget);
    expect(
      find.textContaining('ZZFULLZZ'),
      findsNothing,
      reason: 'maxUiPreviewBytes must cap what the detail view decodes',
    );
  });

  testWidgets('untruncated body still decodes the full byte buffer',
      (tester) async {
    final fullText = jsonEncode({
      'items': [1, 2, 3],
      'marker': 'ZZFULLZZ',
    });
    final fullBytes = Uint8List.fromList(utf8.encode(fullText));

    final record = RequestRecord(
      id: 'rec_complete',
      method: 'GET',
      url: 'https://api.example.com/small',
      statusCode: 200,
      timestamp: DateTime(2026),
      durationMs: 10,
      requestSizeBytes: 0,
      responseSizeBytes: fullBytes.length,
      requestHeaders: const {},
      responseHeaders: const {'content-type': 'application/json'},
      responseContentType: 'application/json',
      responseBodyPreview: fullText,
      responseBodyBytes: fullBytes,
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: BodyTruncation.complete(fullBytes.length),
    );

    final entry = IndexEntry(
      id: record.id,
      method: record.method,
      url: record.url,
      statusCode: record.statusCode,
      durationMs: record.durationMs,
      requestSizeBytes: 0,
      responseSizeBytes: record.responseSizeBytes,
      timestamp: record.timestamp,
      hasError: false,
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: record.responseTruncation,
      bodyLocation: BodyLocation.memory,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailPage(entry: entry, session: _StubSession(record)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Response'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ZZFULLZZ'), findsOneWidget);
  });
}
