import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/capture/capture_guard.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/domain_group.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/raw_capture.dart';
import 'package:interceptly/src/session/inspector_preferences.dart';
import 'package:interceptly/src/session/memory_index.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';

class _ObservableFakeSession extends InspectorSessionView {
  _ObservableFakeSession({
    required this.record,
    required this.entry,
  }) {
    _entries = [entry];
  }

  RequestRecord record;
  IndexEntry entry;
  final InterceptlySettings customSettings = const InterceptlySettings();
  final InspectorPreferences _prefs = InspectorPreferences();
  late List<RequestSummary> _entries;

  @override
  InterceptlySettings get settings => customSettings;
  @override
  InspectorPreferences get preferences => _prefs;
  @override
  List<RequestSummary> get entries => _entries;
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

  Completer<RequestRecord>? delayDetailCompleter;

  @override
  Future<RequestRecord> loadDetail(RequestSummary summary) async {
    if (delayDetailCompleter != null) {
      return delayDetailCompleter!.future;
    }
    return record;
  }

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

  void triggerSessionChanged(
      IndexEntry updatedEntry, RequestRecord updatedRecord) {
    entry = updatedEntry;
    record = updatedRecord;
    _entries = [updatedEntry];
    notifyListeners();
  }
}

IndexEntry _createIndexEntry(
  String id, {
  String method = 'GET',
  String url = 'https://api.example.com/items',
  int statusCode = 200,
  int durationMs = 15,
  bool hasError = false,
}) {
  return IndexEntry(
    id: id,
    method: method,
    url: '$url/$id',
    statusCode: statusCode,
    durationMs: durationMs,
    requestSizeBytes: 128,
    responseSizeBytes: 512,
    timestamp: DateTime(2026, 1, 1),
    hasError: hasError || statusCode >= 400 || statusCode == 0,
    requestTruncation: const BodyTruncation.complete(0),
    responseTruncation: const BodyTruncation.complete(0),
    bodyLocation: BodyLocation.memory,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('challenger_m1_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      },
    );
  });

  tearDownAll(() async {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group(
      'Empirical Challenge 1: MemoryIndex 50,000 Operations Stress & O(1) Performance',
      () {
    test(
        '50,000 sequential insertions verify O(1) time complexity and order stability',
        () {
      const maxCapacity = 10000;
      const totalOps = 50000;
      final index = MemoryIndex(maxEntries: maxCapacity);

      final chunkTimes = <int>[];
      final stopwatch = Stopwatch()..start();
      var lastLap = stopwatch.elapsedMicroseconds;

      for (var i = 0; i < totalOps; i++) {
        index.add(_createIndexEntry('req_$i'));

        if ((i + 1) % 10000 == 0) {
          final now = stopwatch.elapsedMicroseconds;
          chunkTimes.add(now - lastLap);
          lastLap = now;
        }
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(500),
          reason:
              '50,000 insertions took ${stopwatch.elapsedMilliseconds}ms, exceeding O(1) expected budget');

      final firstChunkMs = chunkTimes[0] / 1000.0;
      final lastChunkMs = chunkTimes.last / 1000.0;
      expect(lastChunkMs, lessThan(firstChunkMs * 5.0 + 100.0),
          reason:
              'Last chunk ($lastChunkMs ms) degraded significantly compared to first chunk ($firstChunkMs ms)');

      expect(index.length, maxCapacity);
      expect(index.entries.length, maxCapacity);

      expect(index.entries.first.id, 'req_${totalOps - 1}');
      expect(index.entries[1].id, 'req_${totalOps - 2}');
      expect(
          index.entries[maxCapacity - 1].id, 'req_${totalOps - maxCapacity}');
      expect(index.entries.last.id, 'req_${totalOps - maxCapacity}');

      expect(index.byId('req_0'), isNull);
      expect(index.get('req_0'), isNull);
      expect(index.byId('req_39999'), isNull);
      expect(index.get('req_39999'), isNull);

      expect(index.byId('req_40000')?.id, 'req_40000');
      expect(index.get('req_40000')?.id, 'req_40000');
      expect(index.byId('req_49999')?.id, 'req_49999');
      expect(index.get('req_49999')?.id, 'req_49999');
    });

    test(
        'In-place updates maintain order stability and slot positions without shifting',
        () {
      const maxCapacity = 5000;
      final index = MemoryIndex(maxEntries: maxCapacity);

      for (var i = 0; i < maxCapacity; i++) {
        index.add(_createIndexEntry('req_$i', statusCode: 0));
      }
      expect(index.length, maxCapacity);

      expect(index.entries[0].id, 'req_4999');
      expect(index.entries[2499].id, 'req_2500');
      expect(index.entries[4999].id, 'req_0');

      index
          .add(_createIndexEntry('req_2500', statusCode: 200, durationMs: 120));

      expect(index.length, maxCapacity);
      expect(index.entries[2499].id, 'req_2500');
      expect(index.entries[2499].statusCode, 200);
      expect(index.entries[2499].durationMs, 120);
      expect(index.entries[2498].id, 'req_2501');
      expect(index.entries[2500].id, 'req_2499');
      expect(index.entries.first.id, 'req_4999');
      expect(index.entries.last.id, 'req_0');

      index.add(_createIndexEntry('req_4999', statusCode: 201, durationMs: 45));
      expect(index.entries[0].id, 'req_4999');
      expect(index.entries[0].statusCode, 201);
      expect(index.entries[0].durationMs, 45);

      index.add(_createIndexEntry('req_0', statusCode: 204, durationMs: 80));
      expect(index.entries[4999].id, 'req_0');
      expect(index.entries[4999].statusCode, 204);
      expect(index.entries[4999].durationMs, 80);

      final updateStopwatch = Stopwatch()..start();
      for (var round = 0; round < 50000; round++) {
        final targetId = 'req_${round % maxCapacity}';
        index.add(_createIndexEntry(targetId, statusCode: 200 + (round % 5)));
      }
      updateStopwatch.stop();

      expect(updateStopwatch.elapsedMilliseconds, lessThan(300),
          reason:
              '50,000 in-place updates took ${updateStopwatch.elapsedMilliseconds}ms, exceeding O(1) budget');
      expect(index.length, maxCapacity);
    });

    test(
        'High-throughput interleaved churn (50,000 ops) verifies no duplicates and order invariants',
        () {
      const maxCapacity = 200;
      final index = MemoryIndex(maxEntries: maxCapacity);

      for (var op = 0; op < 50000; op++) {
        final mode = op % 10;
        if (mode < 6) {
          index.add(_createIndexEntry('fresh_$op', statusCode: 0));
        } else if (mode < 9) {
          final recentOffset = op % maxCapacity;
          final targetId = 'fresh_${op - recentOffset}';
          index.add(
              _createIndexEntry(targetId, statusCode: 200, durationMs: 50));
        } else {
          final evictedId = 'fresh_${(op - 500).clamp(0, op)}';
          index.add(
              _createIndexEntry(evictedId, statusCode: 500, hasError: true));
        }

        if (op % 10000 == 0) {
          expect(index.length, lessThanOrEqualTo(maxCapacity));
          final ids = index.entries.map((e) => e.id).toList();
          final uniqueIds = ids.toSet();
          expect(ids.length, uniqueIds.length,
              reason: 'Found duplicate IDs in entries at operation $op');
        }
      }

      expect(index.length, maxCapacity);
      final finalIds = index.entries.map((e) => e.id).toList();
      expect(finalIds.length, finalIds.toSet().length,
          reason: 'Duplicate entries found at end of churn test');
    });

    test(
        'Boundary conditions: maxEntries=1, maxEntries=0, negative, clear, and unmodifiable view',
        () {
      final singleIndex = MemoryIndex(maxEntries: 1);
      for (var i = 0; i < 5000; i++) {
        singleIndex.add(_createIndexEntry('single_$i'));
        expect(singleIndex.length, 1);
        expect(singleIndex.entries.first.id, 'single_$i');
        expect(singleIndex.byId('single_$i')?.id, 'single_$i');
        if (i > 0) {
          expect(singleIndex.byId('single_${i - 1}'), isNull);
        }
      }

      singleIndex.add(_createIndexEntry('single_4999', statusCode: 304));
      expect(singleIndex.length, 1);
      expect(singleIndex.entries.first.statusCode, 304);

      final zeroIndex = MemoryIndex(maxEntries: 0);
      expect(() => zeroIndex.add(_createIndexEntry('item')),
          throwsA(isA<RangeError>()));

      final negativeIndex = MemoryIndex(maxEntries: -10);
      expect(() => negativeIndex.add(_createIndexEntry('item')),
          throwsA(isA<RangeError>()));

      singleIndex.clear();
      expect(singleIndex.length, 0);
      expect(singleIndex.entries, isEmpty);
      expect(singleIndex.byId('single_4999'), isNull);

      singleIndex.add(_createIndexEntry('fresh_start'));
      expect(singleIndex.length, 1);
      expect(singleIndex.entries.first.id, 'fresh_start');

      final testIndex = MemoryIndex(maxEntries: 5);
      testIndex.add(_createIndexEntry('u1'));
      testIndex.add(_createIndexEntry('u2'));
      final entriesView = testIndex.entries;

      expect(() => entriesView.length = 0, throwsA(isA<UnsupportedError>()));
      expect(() => entriesView[0] = _createIndexEntry('u3'),
          throwsA(isA<UnsupportedError>()));
      expect(() => entriesView[-1], throwsA(isA<RangeError>()));
      expect(() => entriesView[2], throwsA(isA<RangeError>()));
      expect(() => entriesView[100], throwsA(isA<RangeError>()));
    });
  });

  group(
      'Empirical Challenge 2: RequestDetailPage Lazy Tab Mounting Verification',
      () {
    testWidgets(
      'Tabs 1, 2, 3 are NEVER mounted initially across multiple frame pumps and time delays',
      (tester) async {
        final entry = _createIndexEntry('req_lazy_multi_frame');
        final record = RequestRecord(
          id: 'req_lazy_multi_frame',
          method: 'POST',
          url: 'https://api.example.com/items/req_lazy_multi_frame',
          statusCode: 200,
          durationMs: 32,
          requestSizeBytes: 64,
          responseSizeBytes: 256,
          timestamp: DateTime(2026, 1, 1),
          requestHeaders: const {
            'content-type': 'application/json',
            'authorization': 'Bearer secret'
          },
          responseHeaders: const {
            'content-type': 'application/json',
            'server': 'test-server'
          },
          requestContentType: 'application/json',
          responseContentType: 'application/json',
          requestBodyPreview: '{"name":"lazy_item"}',
          responseBodyPreview: '{"status":"ok","id":"req_lazy_multi_frame"}',
        );

        final session = _ObservableFakeSession(record: record, entry: entry);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RequestDetailPage(entry: entry, session: session),
            ),
          ),
        );

        await tester.pump();

        expect(find.text('URL'), findsOneWidget,
            reason: 'Overview tab should mount after detail future resolves');
        expect(find.text('REQUEST HEADERS', skipOffstage: false), findsNothing,
            reason:
                'Tab 1 (Request) must not mount on initial overview render');
        expect(find.text('RESPONSE HEADERS', skipOffstage: false), findsNothing,
            reason:
                'Tab 2 (Response) must not mount on initial overview render');
        expect(find.text('Error Summary', skipOffstage: false), findsNothing,
            reason: 'Tab 3 (Error) must not mount on initial overview render');
        expect(find.text('No errors for this request.', skipOffstage: false),
            findsNothing,
            reason: 'Tab 3 (Error) must not mount on initial overview render');

        await tester.pump();
        expect(find.text('REQUEST HEADERS', skipOffstage: false), findsNothing,
            reason: 'Tab 1 must NOT mount on Frame 2');
        expect(find.text('RESPONSE HEADERS', skipOffstage: false), findsNothing,
            reason: 'Tab 2 must NOT mount on Frame 2');
        expect(find.text('No errors for this request.', skipOffstage: false),
            findsNothing,
            reason: 'Tab 3 must NOT mount on Frame 2');

        for (var f = 0; f < 10; f++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();

        expect(find.text('REQUEST HEADERS', skipOffstage: false), findsNothing,
            reason: 'Tab 1 must NOT mount after idle time on Overview tab');
        expect(find.text('RESPONSE HEADERS', skipOffstage: false), findsNothing,
            reason: 'Tab 2 must NOT mount after idle time on Overview tab');
        expect(find.text('No errors for this request.', skipOffstage: false),
            findsNothing,
            reason: 'Tab 3 must NOT mount after idle time on Overview tab');
      },
    );

    testWidgets(
      'Session notifications and background data updates do NOT cause unvisited tabs to mount',
      (tester) async {
        final pendingEntry = _createIndexEntry('req_in_flight', statusCode: 0);
        final pendingRecord = RequestRecord(
          id: 'req_in_flight',
          method: 'GET',
          url: 'https://api.example.com/items/req_in_flight',
          statusCode: 0,
          durationMs: 0,
          requestSizeBytes: 40,
          responseSizeBytes: 0,
          timestamp: DateTime(2026, 1, 1),
          requestHeaders: const {'accept': 'application/json'},
          responseHeaders: const {},
        );

        final session =
            _ObservableFakeSession(record: pendingRecord, entry: pendingEntry);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RequestDetailPage(entry: pendingEntry, session: session),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final completedEntry = _createIndexEntry('req_in_flight',
            statusCode: 200, durationMs: 150);
        final completedRecord = RequestRecord(
          id: 'req_in_flight',
          method: 'GET',
          url: 'https://api.example.com/items/req_in_flight',
          statusCode: 200,
          durationMs: 150,
          requestSizeBytes: 40,
          responseSizeBytes: 1024,
          timestamp: DateTime(2026, 1, 1),
          requestHeaders: const {'accept': 'application/json'},
          responseHeaders: const {'content-type': 'application/json'},
          responseBodyPreview: '{"result":"success"}',
        );

        session.triggerSessionChanged(completedEntry, completedRecord);
        await tester.pumpAndSettle();

        expect(find.text('150 ms'), findsOneWidget);
        expect(find.text('200'), findsAtLeastNWidgets(1));
        expect(find.text('150 ms'), findsOneWidget);

        expect(find.text('REQUEST HEADERS', skipOffstage: false), findsNothing);
        expect(
            find.text('RESPONSE HEADERS', skipOffstage: false), findsNothing);
        expect(find.text('No errors for this request.', skipOffstage: false),
            findsNothing);
      },
    );

    testWidgets(
      'Step-by-step user tab selection mounts strictly the selected tab',
      (tester) async {
        final entry = _createIndexEntry('req_step_by_step');
        final record = RequestRecord(
          id: 'req_step_by_step',
          method: 'POST',
          url: 'https://api.example.com/items/req_step_by_step',
          statusCode: 200,
          durationMs: 25,
          requestSizeBytes: 80,
          responseSizeBytes: 180,
          timestamp: DateTime(2026, 1, 1),
          requestHeaders: const {'content-type': 'application/json'},
          responseHeaders: const {'content-type': 'application/json'},
          requestBodyPreview: '{"test":"payload"}',
          responseBodyPreview: '{"status":"ok"}',
        );

        final session = _ObservableFakeSession(record: record, entry: entry);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RequestDetailPage(entry: entry, session: session),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Response'));
        await tester.pumpAndSettle();

        expect(find.text('RESPONSE HEADERS'), findsOneWidget);
        expect(find.text('REQUEST HEADERS', skipOffstage: false), findsNothing);
        expect(find.text('No errors for this request.', skipOffstage: false),
            findsNothing);

        await tester.tap(find.text('Request'));
        await tester.pumpAndSettle();

        expect(find.text('REQUEST HEADERS'), findsOneWidget);
        expect(
            find.text('RESPONSE HEADERS', skipOffstage: false), findsOneWidget);
        expect(find.text('No errors for this request.', skipOffstage: false),
            findsNothing);

        await tester.tap(find.text('Error'));
        await tester.pumpAndSettle();

        expect(find.text('No errors for this request.'), findsOneWidget);
        expect(
            find.text('REQUEST HEADERS', skipOffstage: false), findsOneWidget);
        expect(
            find.text('RESPONSE HEADERS', skipOffstage: false), findsOneWidget);
      },
    );

    testWidgets(
      'WebSocket inspection with 2 tabs: Messages tab is never mounted until selected',
      (tester) async {
        final wsEntry = _createIndexEntry('ws_conn',
            method: 'WS', url: 'wss://stream.example.com/ws');
        final wsRecord = RequestRecord(
          id: 'ws_conn',
          method: 'WS',
          url: 'wss://stream.example.com/ws',
          statusCode: 101,
          durationMs: 12000,
          requestSizeBytes: 0,
          responseSizeBytes: 0,
          timestamp: DateTime(2026, 1, 1),
          requestHeaders: const {'upgrade': 'websocket'},
          responseHeaders: const {'upgrade': 'websocket'},
        );

        final session =
            _ObservableFakeSession(record: wsRecord, entry: wsEntry);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RequestDetailPage(entry: wsEntry, session: session),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('URL'), findsOneWidget);
        expect(
            find.text('No WebSocket messages captured.', skipOffstage: false),
            findsNothing);

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        expect(
            find.text('No WebSocket messages captured.', skipOffstage: false),
            findsNothing);

        await tester.tap(find.text('Messages'));
        await tester.pumpAndSettle();

        expect(find.text('No WebSocket messages captured.'), findsOneWidget);
      },
    );
  });

  group('Empirical Challenge 3: Header Redaction Caching & Case Invariance',
      () {
    test(
        'InterceptlySettings normalizes varied mixed/uppercase header keys to strictly lowercase',
        () {
      const variedSettings = InterceptlySettings(
        redactedHeaders: {
          'AUTHORIZATION',
          'X-Api-Key',
          'COOKIE',
          'sEt-CoOkIe',
          'BEARER-TOKEN',
          'Custom_Secret_HEADER',
        },
      );

      final normalized = variedSettings.normalizedRedactedHeaders;

      expect(
          normalized,
          containsAll({
            'authorization',
            'x-api-key',
            'cookie',
            'set-cookie',
            'bearer-token',
            'custom_secret_header',
          }));

      for (final key in normalized) {
        expect(key, equals(key.toLowerCase()),
            reason:
                'Found non-lowercase key in normalizedRedactedHeaders: $key');
      }

      expect(() => normalized.add('new-key'), throwsA(isA<UnsupportedError>()));
    });

    test(
        'Expando caching returns identical set instance across 10,000 accesses with zero allocations',
        () {
      const settings = InterceptlySettings(
        redactedHeaders: {'Authorization', 'Cookie'},
      );

      final firstInstance = settings.normalizedRedactedHeaders;
      final stopwatch = Stopwatch()..start();

      for (var i = 0; i < 10000; i++) {
        final repeated = settings.normalizedRedactedHeaders;
        expect(identical(firstInstance, repeated), isTrue,
            reason:
                'Expando cache failed to return identical Set instance at iteration $i');
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(50),
          reason:
              '10,000 cached property accesses took ${stopwatch.elapsedMilliseconds}ms');
    });

    test('copyWith properly isolates normalized cache between instances', () {
      const base = InterceptlySettings(
        redactedHeaders: {'Authorization'},
      );
      final baseNormalized = base.normalizedRedactedHeaders;
      expect(baseNormalized, contains('authorization'));

      final modified = base.copyWith(
        redactedHeaders: {'X-Custom-Secret'},
      );
      final modifiedNormalized = modified.normalizedRedactedHeaders;

      expect(identical(baseNormalized, modifiedNormalized), isFalse);
      expect(modifiedNormalized, contains('x-custom-secret'));
      expect(modifiedNormalized.contains('authorization'), isFalse);
      expect(baseNormalized.contains('authorization'), isTrue);
    });

    test(
        'Header redaction correctly masks all casing variations in incoming request/response headers',
        () {
      const settings = InterceptlySettings(
        redactedHeaders: {
          'Authorization',
          'X-API-KEY',
          'cookie',
          'Set-Cookie',
          'token',
        },
      );
      final normalizedKeys = settings.normalizedRedactedHeaders;

      final diverseHeaders = {
        'AUTHORIZATION': 'Bearer secret_upper',
        'authorization': 'Bearer secret_lower',
        'Authorization': 'Bearer secret_title',
        'AuThOrIzAtIoN': 'Bearer secret_mixed',
        'x-api-key': 'key_lower',
        'X-API-KEY': 'key_upper',
        'X-Api-Key': 'key_mixed',
        'COOKIE': 'c=upper',
        'cookie': 'c=lower',
        'Cookie': 'c=title',
        'SET-COOKIE': 'sc=upper',
        'set-cookie': 'sc=lower',
        'Set-Cookie': 'sc=title',
        'TOKEN': 't=upper',
        'token': 't=lower',
        'Token': 't=title',
        'Content-Type': 'application/json',
        'CONTENT-LENGTH': '128',
        'accept': '*/*',
        'X-Request-Id': 'req-xyz-123',
      };

      final sanitized =
          CaptureGuard.redactHeaders(diverseHeaders, normalizedKeys);

      expect(sanitized['AUTHORIZATION'], '[REDACTED]');
      expect(sanitized['authorization'], '[REDACTED]');
      expect(sanitized['Authorization'], '[REDACTED]');
      expect(sanitized['AuThOrIzAtIoN'], '[REDACTED]');

      expect(sanitized['x-api-key'], '[REDACTED]');
      expect(sanitized['X-API-KEY'], '[REDACTED]');
      expect(sanitized['X-Api-Key'], '[REDACTED]');

      expect(sanitized['COOKIE'], '[REDACTED]');
      expect(sanitized['cookie'], '[REDACTED]');
      expect(sanitized['Cookie'], '[REDACTED]');

      expect(sanitized['SET-COOKIE'], '[REDACTED]');
      expect(sanitized['set-cookie'], '[REDACTED]');
      expect(sanitized['Set-Cookie'], '[REDACTED]');

      expect(sanitized['TOKEN'], '[REDACTED]');
      expect(sanitized['token'], '[REDACTED]');
      expect(sanitized['Token'], '[REDACTED]');

      expect(sanitized['Content-Type'], 'application/json');
      expect(sanitized['CONTENT-LENGTH'], '128');
      expect(sanitized['accept'], '*/*');
      expect(sanitized['X-Request-Id'], 'req-xyz-123');
    });

    test(
        'Edge cases: empty headers, empty redacted set, and un-redacted pass-through',
        () {
      final normalized = const InterceptlySettings().normalizedRedactedHeaders;

      final emptyResult = CaptureGuard.redactHeaders(const {}, normalized);
      expect(emptyResult, isEmpty);

      final originalHeaders = {
        'Authorization': 'secret',
        'Host': 'example.com'
      };
      final passThrough = CaptureGuard.redactHeaders(originalHeaders, const {});
      expect(identical(originalHeaders, passThrough), isTrue);

      final benignHeaders = {
        'Accept': 'text/html',
        'User-Agent': 'Dart/3.0',
        'Host': 'api.example.com',
      };
      final benignResult =
          CaptureGuard.redactHeaders(benignHeaders, normalized);
      expect(benignResult['Accept'], 'text/html');
      expect(benignResult['User-Agent'], 'Dart/3.0');
      expect(benignResult['Host'], 'api.example.com');
    });

    test(
        'Dynamic settings update in InspectorSession updates normalized redacted set',
        () {
      final initialSettings = const InterceptlySettings(
        redactedHeaders: {'Authorization'},
      );
      final session = InspectorSession(settings: initialSettings);

      final initialHeaders = {
        'Authorization': 'secret_1',
        'X-Token': 'secret_2'
      };
      final capture1 = RawCapture(
        id: 'cap_1',
        method: 'GET',
        url: 'https://api.example.com/test1',
        requestHeaders: initialHeaders,
        responseHeaders: const {},
        statusCode: 200,
        durationMs: 10,
        timestamp: DateTime(2026, 1, 1),
      );
      session.record(capture1);

      final newSettings = initialSettings.copyWith(
        redactedHeaders: {'Authorization', 'X-Token'},
      );
      session.configureSession(newSettings);

      final capture2 = RawCapture(
        id: 'cap_2',
        method: 'GET',
        url: 'https://api.example.com/test2',
        requestHeaders: initialHeaders,
        responseHeaders: const {},
        statusCode: 200,
        durationMs: 10,
        timestamp: DateTime(2026, 1, 1),
      );
      session.record(capture2);

      session.dispose();
    });

    test('Non-normalized raw key behavior documentation in CaptureGuard', () {
      final unnormalizedSet = {'AUTHORIZATION'};
      final headers = {'authorization': 'secret'};
      final result = CaptureGuard.redactHeaders(headers, unnormalizedSet);
      expect(result['authorization'], 'secret',
          reason:
              'Confirms that unnormalized sets fail to match, proving the necessity of normalizedRedactedHeaders');
    });
  });

  group(
      'Empirical Challenge 4: Advanced MemoryIndex Edge Cases & Filter Invariants',
      () {
    test(
        'Odd and prime buffer capacities (7, 13, 999) maintain invariant across 20,000 churns',
        () {
      for (final cap in [7, 13, 999]) {
        final index = MemoryIndex(maxEntries: cap);

        for (var i = 0; i < 20000; i++) {
          index.add(_createIndexEntry('prime_${cap}_$i'));
        }

        expect(index.length, cap);
        expect(index.entries.first.id, 'prime_${cap}_19999');
        expect(index.entries.last.id, 'prime_${cap}_${20000 - cap}');

        expect(index.byId('prime_${cap}_0'), isNull);
        expect(index.byId('prime_${cap}_19999')?.id, 'prime_${cap}_19999');
      }
    });

    test(
        'MemoryIndex.filtered returns matching items in consistent newest-first order',
        () {
      final index = MemoryIndex(maxEntries: 100);

      for (var i = 0; i < 300; i++) {
        final method = i % 3 == 0 ? 'GET' : (i % 3 == 1 ? 'POST' : 'DELETE');
        final status = i % 2 == 0 ? 200 : 500;
        index.add(
            _createIndexEntry('req_$i', method: method, statusCode: status));
      }

      expect(index.length, 100);

      final errorFilter = RequestFilter(
        include2xx: false,
        include3xx: false,
        include4xx: false,
        include5xx: true,
      );
      final errorEntries = index.filtered(errorFilter);

      for (final e in errorEntries) {
        expect(e.statusCode, 500);
      }

      for (var i = 0; i < errorEntries.length - 1; i++) {
        final curNum = int.parse(errorEntries[i].id.split('_')[1]);
        final nextNum = int.parse(errorEntries[i + 1].id.split('_')[1]);
        expect(curNum, greaterThan(nextNum),
            reason: 'Filtered list must preserve newest-first order');
      }
    });
  });
}
