import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:interceptly/src/export/curl_generator.dart';
import 'package:interceptly/src/export/har_exporter.dart';
import 'package:interceptly/src/export/postman_exporter.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/domain_group.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';
import 'package:interceptly/src/model/network_simulation.dart';
import 'package:interceptly/src/model/raw_capture.dart';
import 'package:interceptly/src/model/request_filter.dart';
import 'package:interceptly/src/model/request_record.dart';
import 'package:interceptly/src/model/request_summary.dart';
import 'package:interceptly/src/session/body_decode_service.dart';
import 'package:interceptly/src/session/inspector_preferences.dart';
import 'package:interceptly/src/session/inspector_session.dart';
import 'package:interceptly/src/session/inspector_session_view.dart';
import 'package:interceptly/src/share/interceptly_share.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';
import 'package:interceptly/src/ui/detail/share_handler.dart';
import 'package:interceptly/src/ui/widgets/json_viewer.dart';

class _MockSessionView extends InspectorSessionView {
  _MockSessionView({required this.record, required this.entry});

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

class _FakeShare extends InterceptlyShare {
  String? sharedFilePath;
  String? sharedMimeType;
  bool shareCalled = false;

  @override
  Future<bool> shareFile({
    required String filePath,
    String? subject,
    String? text,
    String? mimeType,
    Rect? origin,
  }) async {
    shareCalled = true;
    sharedFilePath = filePath;
    sharedMimeType = mimeType;
    return true;
  }
}

class _MockRenderBox extends RenderBox {
  @override
  bool get hasSize => true;

  @override
  Size get size => const Size(40, 40);

  @override
  Offset localToGlobal(Offset point, {RenderObject? ancestor}) => point;
}

class _MockContext extends Fake implements BuildContext {
  _MockContext(this._box);
  final RenderBox _box;

  @override
  RenderObject? findRenderObject() => _box;
}

class _MockGlobalKey extends GlobalKey {
  const _MockGlobalKey(this._context) : super.constructor();
  final BuildContext _context;

  @override
  BuildContext? get currentContext => _context;
}

RequestRecord _buildTestRecord({
  required String id,
  String method = 'GET',
  String url = 'https://api.example.com/adversarial',
  int statusCode = 200,
  int responseSizeBytes = 0,
  Uint8List? responseBodyBytes,
  String? responseBodyPreview,
  String? responseContentType = 'application/json',
  bool isBodyTruncated = false,
  bool isUiTruncated = false,
}) {
  return RequestRecord(
    id: id,
    method: method,
    url: url,
    statusCode: statusCode,
    durationMs: 25,
    requestSizeBytes: 0,
    responseSizeBytes: responseSizeBytes,
    timestamp: DateTime.now(),
    requestHeaders: const {},
    responseHeaders: {'content-type': responseContentType ?? 'application/json'},
    responseContentType: responseContentType,
    requestBodyPreview: null,
    responseBodyPreview: responseBodyPreview,
    requestBodyBytes: null,
    responseBodyBytes: responseBodyBytes,
    isBodyTruncated: isBodyTruncated,
    isUiTruncated: isUiTruncated,
  );
}

IndexEntry _buildTestIndexEntry(RequestRecord r) {
  return IndexEntry(
    id: r.id,
    method: r.method,
    url: r.url,
    statusCode: r.statusCode,
    durationMs: r.durationMs,
    requestSizeBytes: r.requestSizeBytes,
    responseSizeBytes: r.responseSizeBytes,
    timestamp: r.timestamp,
    hasError: r.hasError,
    isBodyTruncated: r.isBodyTruncated,
    bodyLocation: BodyLocation.memory,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Challenger M2: JsonViewer Corner Cases', () {
    testWidgets('handles null data by rendering fallback text gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: JsonViewer(data: null),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Data'), findsOneWidget);
      expect(JsonViewer.formatData(null), equals('null'));
      expect(JsonViewer.countMatches(null, 'null'), equals(1));
    });

    testWidgets('handles empty Map and empty List without collapsing or error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(height: 100, width: 200, child: JsonViewer(data: {})),
                SizedBox(height: 100, width: 200, child: JsonViewer(data: [])),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('{}'), findsOneWidget);
      expect(find.text('[]'), findsOneWidget);
    });

    testWidgets('handles nested empty collections and empty string scalars', (tester) async {
      final nestedEmpty = {
        'empty_map': {},
        'empty_list': [],
        'empty_string': '',
        'nested': {
          'deep_empty_list': [],
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              width: 300,
              child: JsonViewer(data: nestedEmpty),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('"empty_map"'), findsOneWidget);
      expect(find.textContaining('"empty_list"'), findsOneWidget);
      expect(find.textContaining('"empty_string"'), findsOneWidget);
      expect(find.textContaining('""'), findsOneWidget);
    });

    testWidgets('handles single extremely long line (50,000 chars) without layout crashes', (tester) async {
      final longKey = 'key_${'a' * 25000}';
      final longVal = 'val_${'b' * 25000}';
      final data = {longKey: longVal};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              width: 300,
              child: JsonViewer(data: data),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ListView), findsNWidgets(2));
    });

    testWidgets('handles special characters, unicode, emojis, and regex query characters', (tester) async {
      final specialData = {
        'unicode': 'Tiếng Việt có dấu: ă, â, đ, ê, ô, ơ, ư',
        'emojis': '🚀🔥🎉💎✨',
        'symbols': '<script>alert("xss")</script> & "quotes" \'single\' \\backslash\\',
        'special_math': 'x = (a + b) * [c - d] ^ {e} | f \$ g',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              width: 400,
              child: JsonViewer(
                data: specialData,
                searchQuery: r'.*+?^$()[]{}\|',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('🚀🔥🎉💎✨'), findsOneWidget);
      expect(find.textContaining('Tiếng Việt'), findsOneWidget);

      final countSpecial = JsonViewer.countMatches(specialData, r'(a + b)');
      expect(countSpecial, equals(1));
    });

    testWidgets('handles unparsed strings with unmatched braces and corrupted JSON', (tester) async {
      const brokenJson = '{"unmatched": [1, 2, 3, {"missing_close": true';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              width: 400,
              child: JsonViewer(data: brokenJson),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(JsonViewer.formatData(brokenJson), equals(brokenJson));
    });

    testWidgets('survives rapid consecutive folding and unfolding toggles', (tester) async {
      final deepData = {
        'layer_1': {
          'layer_2': {
            'layer_3': {
              'layer_4': {
                'value': 42,
              },
            },
          },
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              width: 400,
              child: JsonViewer(data: deepData),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('42'), findsOneWidget);

      final foldIcon = find.byIcon(Icons.arrow_drop_down).first;

      for (int i = 0; i < 10; i++) {
        await tester.tap(foldIcon);
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      await tester.tap(foldIcon);
      await tester.pumpAndSettle();

      final has42 = find.textContaining('42').evaluate().isNotEmpty;
      final hasEllipsis = find.textContaining('…').evaluate().isNotEmpty;
      expect(has42 || hasEllipsis, isTrue);
    });
  });

  group('Challenger M2: Boundary Cases for Storage', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('interceptly_storage_boundary_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (call.method == 'getTemporaryDirectory') return tempDir.path;
          return null;
        },
      );
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('exact 2MB payload: full bytes kept in file and UI is NOT truncated', () async {
      final session = InspectorSession(
        settings: const InterceptlySettings(
          maxBodyBytes: 50 * 1024 * 1024,
          maxUiPreviewBytes: 2 * 1024 * 1024,
        ),
      );
      await session.initialize();

      const exact2Mb = 2 * 1024 * 1024;
      final payload = Uint8List(exact2Mb);
      payload.fillRange(0, exact2Mb, 65);

      session.record(
        RawCapture(
          id: 'exact_2mb',
          method: 'POST',
          url: 'https://api.example.com/2mb',
          requestHeaders: const {},
          responseHeaders: const {'content-type': 'text/plain'},
          statusCode: 200,
          timestamp: DateTime.now(),
          durationMs: 50,
          responseBodyBytes: RawCapture.wrapBytes(payload),
          responseContentType: 'text/plain',
        ),
      );

      final end = DateTime.now().add(const Duration(seconds: 10));
      while (session.entries.isEmpty) {
        if (DateTime.now().isAfter(end)) throw StateError('Timeout waiting for entry');
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final entry = session.entries.first;
      final record = await session.loadDetail(entry);

      expect(record.responseBodyBytes, isNotNull);
      expect(record.responseBodyBytes!.length, equals(exact2Mb));
      expect(record.isBodyTruncated, isFalse);
      expect(record.isUiTruncated, isFalse);
      expect(record.responseBodyPreview!.length, equals(exact2Mb));

      await session.dispose();
    });

    test('2MB + 1 byte payload: full bytes kept in file and UI IS truncated', () async {
      final session = InspectorSession(
        settings: const InterceptlySettings(
          maxBodyBytes: 50 * 1024 * 1024,
          maxUiPreviewBytes: 2 * 1024 * 1024,
        ),
      );
      await session.initialize();

      const twoMbPlus1 = 2 * 1024 * 1024 + 1;
      final payload = Uint8List(twoMbPlus1);
      payload.fillRange(0, twoMbPlus1, 66);

      session.record(
        RawCapture(
          id: '2mb_plus_1',
          method: 'POST',
          url: 'https://api.example.com/2mb_plus_1',
          requestHeaders: const {},
          responseHeaders: const {'content-type': 'text/plain'},
          statusCode: 200,
          timestamp: DateTime.now(),
          durationMs: 60,
          responseBodyBytes: RawCapture.wrapBytes(payload),
          responseContentType: 'text/plain',
        ),
      );

      final end = DateTime.now().add(const Duration(seconds: 10));
      while (session.entries.isEmpty) {
        if (DateTime.now().isAfter(end)) throw StateError('Timeout waiting for entry');
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final entry = session.entries.first;
      final record = await session.loadDetail(entry);

      expect(record.responseBodyBytes, isNotNull);
      expect(record.responseBodyBytes!.length, equals(twoMbPlus1));
      expect(record.isBodyTruncated, isFalse);
      expect(record.isUiTruncated, isTrue);
      expect(record.responseBodyPreview!.length, equals(2 * 1024 * 1024));

      await session.dispose();
    });

    test('0 bytes payload: empty buffers handle cleanly without exceptions', () async {
      final session = InspectorSession();
      await session.initialize();

      session.record(
        RawCapture(
          id: 'empty_bytes',
          method: 'GET',
          url: 'https://api.example.com/empty',
          requestHeaders: const {},
          responseHeaders: const {'content-type': 'application/json'},
          statusCode: 204,
          timestamp: DateTime.now(),
          durationMs: 10,
          requestBodyBytes: RawCapture.wrapBytes(Uint8List(0)),
          responseBodyBytes: RawCapture.wrapBytes(Uint8List(0)),
          responseContentType: 'application/json',
        ),
      );

      final end = DateTime.now().add(const Duration(seconds: 10));
      while (session.entries.isEmpty) {
        if (DateTime.now().isAfter(end)) throw StateError('Timeout waiting for entry');
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final entry = session.entries.first;
      final record = await session.loadDetail(entry);

      expect(record.isUiTruncated, isFalse);
      expect(record.isBodyTruncated, isFalse);

      final curl = CurlGenerator.fromRecord(record);
      expect(curl, isNot(contains('--data-raw')));

      final harJson = HarExporter.toJson([record]);
      expect(harJson, contains('"log"'));

      final postmanJson = PostmanExporter.toJson([record]);
      expect(postmanJson, contains('"info"'));

      await session.dispose();
    });

    test('negative and zero maxBodyBytes treated as unlimited storage cap', () async {
      for (final maxBodySetting in [0, -1, -500]) {
        final session = InspectorSession(
          settings: InterceptlySettings(
            maxBodyBytes: maxBodySetting,
            maxUiPreviewBytes: 100 * 1024,
          ),
        );
        await session.initialize();

        const testSize = 250 * 1024;
        final payload = Uint8List(testSize);
        payload.fillRange(0, testSize, 70);

        session.record(
          RawCapture(
            id: 'unlimited_$maxBodySetting',
            method: 'POST',
            url: 'https://api.example.com/unlimited',
            requestHeaders: const {},
            responseHeaders: const {'content-type': 'text/plain'},
            statusCode: 200,
            timestamp: DateTime.now(),
            durationMs: 20,
            responseBodyBytes: RawCapture.wrapBytes(payload),
            responseContentType: 'text/plain',
          ),
        );

        final end = DateTime.now().add(const Duration(seconds: 10));
        while (session.entries.isEmpty) {
          if (DateTime.now().isAfter(end)) throw StateError('Timeout waiting for entry');
          await Future.delayed(const Duration(milliseconds: 50));
        }

        final entry = session.entries.first;
        final record = await session.loadDetail(entry);

        expect(record.responseBodyBytes!.length, equals(testSize));
        expect(record.isBodyTruncated, isFalse);
        expect(record.isUiTruncated, isTrue);

        await session.dispose();
      }
    });

    test('BodyDecodeService.unpackToBytes binary format boundaries', () {
      final headerOnly = Uint8List(9);
      final bd = ByteData.sublistView(headerOnly);
      bd.setUint32(0, 0xFFFFFFFF, Endian.big);
      bd.setUint32(4, 0xFFFFFFFF, Endian.big);
      headerOnly[8] = 0;

      final unpacked = BodyDecodeService.unpackToBytes(headerOnly);
      expect(unpacked.$1, isNull);
      expect(unpacked.$2, isNull);
      expect(unpacked.$3, isFalse);

      final truncatedFlag = Uint8List.fromList(headerOnly);
      truncatedFlag[8] = 1;
      final unpackedTrunc = BodyDecodeService.unpackToBytes(truncatedFlag);
      expect(unpackedTrunc.$3, isTrue);

      final corrupted = Uint8List(5);
      final unpackedCorrupted = BodyDecodeService.unpackToBytes(corrupted);
      expect(unpackedCorrupted.$1, isNull);
      expect(unpackedCorrupted.$2, isNull);
      expect(unpackedCorrupted.$3, isFalse);
    });
  });

  group('Challenger M2: UI Truncation Banner and Export Action', () {
    late Directory shareTempDir;

    setUp(() async {
      shareTempDir = await Directory.systemTemp.createTemp('interceptly_share_group_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (call.method == 'getTemporaryDirectory') return shareTempDir.path;
          return null;
        },
      );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      try {
        await shareTempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('getTemporaryDirectory resolves under standard unit test', () async {
      final dir = await getTemporaryDirectory();
      expect(dir.path, equals(shareTempDir.path));
    });

    testWidgets('banner is not displayed when isUiTruncated is true', (tester) async {
      const totalSize = 3 * 1024 * 1024;
      final record = _buildTestRecord(
        id: 'banner_trunc',
        responseSizeBytes: totalSize,
        responseBodyBytes: Uint8List(totalSize),
        responseBodyPreview: '{"test":"preview"}',
        isUiTruncated: true,
      );
      final entry = _buildTestIndexEntry(record);
      final session = _MockSessionView(record: record, entry: entry);

      await tester.pumpWidget(
        MaterialApp(
          home: RequestDetailPage(
            entry: entry,
            session: session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Response'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Body truncated preview'), findsNothing);
      expect(find.text('Export Full'), findsNothing);
      expect(find.textContaining('preview'), findsOneWidget);
    });

    testWidgets('banner does not display when payload is <= 2MB and untruncated', (tester) async {
      const smallSize = 2 * 1024 * 1024;
      final record = _buildTestRecord(
        id: 'banner_small',
        responseSizeBytes: smallSize,
        responseBodyBytes: Uint8List(smallSize),
        responseBodyPreview: '{"test":"small"}',
        isUiTruncated: false,
        isBodyTruncated: false,
      );
      final entry = _buildTestIndexEntry(record);
      final session = _MockSessionView(record: record, entry: entry);

      await tester.pumpWidget(
        MaterialApp(
          home: RequestDetailPage(
            entry: entry,
            session: session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Response'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Body truncated preview'), findsNothing);
      expect(find.text('Export Full'), findsNothing);
    });

    test('ShareHandler exportResponseBodyFile writes complete binary payload file', () async {
      final fakeShare = _FakeShare();
      final renderBox = _MockRenderBox();
      final mockContext = _MockContext(renderBox);
      final mockFabKey = _MockGlobalKey(mockContext);
      final fullBytes = Uint8List.fromList(utf8.encode('{"complete_file_payload": true, "size": 3145728}'));

      final record = _buildTestRecord(
        id: 'rec_share_full',
        responseSizeBytes: fullBytes.length,
        responseBodyBytes: fullBytes,
        responseContentType: 'application/json',
        isUiTruncated: true,
      );

      final handler = ShareHandler.withShare(
        context: mockContext,
        fabKey: mockFabKey,
        share: fakeShare,
      );

      await handler.exportResponseBodyFile(record);

      expect(fakeShare.shareCalled, isTrue);
      expect(fakeShare.sharedFilePath, isNotNull);
      expect(fakeShare.sharedMimeType, equals('application/json'));

      final exportedFile = File(fakeShare.sharedFilePath!);
      expect(exportedFile.existsSync(), isTrue);
      final writtenBytes = await exportedFile.readAsBytes();
      expect(writtenBytes, equals(fullBytes));
    });

    test('ShareHandler exportResponseBodyFile handles null or empty bodies cleanly without writing file', () async {
      final fakeShare = _FakeShare();
      final renderBox = _MockRenderBox();
      final mockContext = _MockContext(renderBox);
      final mockFabKey = _MockGlobalKey(mockContext);

      final record = _buildTestRecord(
        id: 'rec_empty_share',
        responseSizeBytes: 0,
        responseBodyBytes: null,
        responseBodyPreview: null,
        isUiTruncated: false,
      );

      final handler = ShareHandler.withShare(
        context: mockContext,
        fabKey: mockFabKey,
        share: fakeShare,
      );

      await handler.exportResponseBodyFile(record);

      expect(fakeShare.shareCalled, isFalse);
      expect(fakeShare.sharedFilePath, isNull);
    });
  });
}
