// ignore_for_file: invalid_use_of_internal_member

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/body_decode_service.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/ui/detail/detail_search.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';

class _FakeScopeController extends InterceptlyScopeController {
  _FakeScopeController({required this.record, required super.engine});

  final RequestRecord record;

  @override
  Future<RequestRecord> loadDetail(RequestSummary summary) async => record;

  @override
  Future<RequestRecord> loadDetailById(String id) async => record;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('BodyDecodeService.repairTruncatedJson', () {
    test('repairs string cut mid-value', () {
      const input = '{"id": 1, "name": "Alice';
      final repaired = BodyDecodeService.repairTruncatedJson(input);
      expect(repaired, isNotNull);
      final decoded = jsonDecode(repaired!) as Map<String, dynamic>;
      expect(decoded['id'], equals(1));
      expect(decoded['name'], equals('Alice'));
    });

    test('repairs object cut after colon', () {
      const input = '{"id": 1, "name": ';
      final repaired = BodyDecodeService.repairTruncatedJson(input);
      expect(repaired, isNotNull);
      final decoded = jsonDecode(repaired!) as Map<String, dynamic>;
      expect(decoded['id'], equals(1));
      expect(decoded['name'], isNull);
    });

    test('repairs object cut mid-key', () {
      const input = '{"id": 1, "use';
      final repaired = BodyDecodeService.repairTruncatedJson(input);
      expect(repaired, isNotNull);
      final decoded = jsonDecode(repaired!) as Map<String, dynamic>;
      expect(decoded['id'], equals(1));
      expect(decoded['use'], isNull);
    });

    test('repairs array cut after comma', () {
      const input = '[1, 2, 3, ';
      final repaired = BodyDecodeService.repairTruncatedJson(input);
      expect(repaired, isNotNull);
      final decoded = jsonDecode(repaired!) as List<dynamic>;
      expect(decoded, equals([1, 2, 3]));
    });

    test('repairs deep nested structures', () {
      const input = '{"user": {"profile": {"tags": ["admin", "dev';
      final repaired = BodyDecodeService.repairTruncatedJson(input);
      expect(repaired, isNotNull);
      final decoded = jsonDecode(repaired!) as Map<String, dynamic>;
      expect(
        (decoded['user'] as Map)['profile']['tags'],
        equals(['admin', 'dev']),
      );
    });

    test('repairs partial booleans and nulls', () {
      expect(
        (jsonDecode(BodyDecodeService.repairTruncatedJson('{"flag": tru')!)
            as Map)['flag'],
        isTrue,
      );
      expect(
        (jsonDecode(BodyDecodeService.repairTruncatedJson('{"flag": fal')!)
            as Map)['flag'],
        isFalse,
      );
      expect(
        (jsonDecode(BodyDecodeService.repairTruncatedJson('{"data": nul')!)
            as Map)['data'],
        isNull,
      );
    });

    test('repairs incomplete floats ending with dot', () {
      final repaired = BodyDecodeService.repairTruncatedJson('{"pi": 3.');
      expect(repaired, isNotNull);
      expect((jsonDecode(repaired!) as Map)['pi'], equals(3.0));
    });

    test('repairs trailing escaped backslash in string', () {
      const input = '{"path": "C:\\\\folder\\\\';
      final repaired = BodyDecodeService.repairTruncatedJson(input);
      expect(repaired, isNotNull);
      final decoded = jsonDecode(repaired!) as Map<String, dynamic>;
      expect(decoded['path'], isNotNull);
    });

    test('returns null for non-JSON content', () {
      expect(
          BodyDecodeService.repairTruncatedJson(
              '<html><body>500 Internal Error</body></html>'),
          isNull);
      expect(BodyDecodeService.repairTruncatedJson('Plain text error message'),
          isNull);
      expect(BodyDecodeService.repairTruncatedJson(''), isNull);
    });
  });

  group('BodyDecodeService.decodeJsonLenient', () {
    test('returns valid Map directly when input is complete JSON', () {
      final result = BodyDecodeService.decodeJsonLenient('{"status": "ok"}');
      expect(result, isA<Map<String, dynamic>>());
      expect((result as Map)['status'], equals('ok'));
    });

    test('returns repaired Map when input is truncated JSON', () {
      final result =
          BodyDecodeService.decodeJsonLenient('{"items": [{"id": 1}, {"id": 2');
      expect(result, isA<Map<String, dynamic>>());
      final items = (result as Map)['items'] as List;
      expect(items.length, equals(2));
      expect(items[0]['id'], equals(1));
      expect(items[1]['id'], equals(2));
    });

    test('returns raw string unchanged when input is plain text', () {
      const text = 'Service Unavailable';
      final result = BodyDecodeService.decodeJsonLenient(text);
      expect(result, equals(text));
    });
  });

  group('RequestDetailPage & Search Integration with Lenient JSON', () {
    testWidgets(
        'renders truncated JSON into full virtualized JsonViewer with folding nodes',
        (tester) async {
      const truncatedJson =
          '{"response_status": "success", "users": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bo';
      final record = RequestRecord(
        id: 'rec_trunc_json_1',
        method: 'GET',
        url: 'https://api.example.com/users',
        statusCode: 200,
        timestamp: DateTime.now(),
        durationMs: 45,
        requestHeaders: {},
        responseHeaders: {'content-type': 'application/json'},
        responseContentType: 'application/json',
        responseBodyPreview: truncatedJson,
        responseBodyBytes: Uint8List.fromList(utf8.encode(truncatedJson)),
        requestSizeBytes: 0,
        responseSizeBytes: truncatedJson.length,
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
        responseTruncation: const BodyTruncation(
          originalBytes: 7000000,
          retainedBytes: 5000000,
          stage: TruncationStage.storage,
        ),
        bodyLocation: BodyLocation.memory,
      );
      final engine = InterceptlyEngine();
      final scope = _FakeScopeController(record: record, engine: engine);

      await tester.pumpWidget(
        MaterialApp(
          home: InterceptlyScope(
            controller: scope,
            child: RequestDetailPage(
              entry: entry,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Response'));
      await tester.pumpAndSettle();

      expect(find.byType(JsonViewer), findsWidgets);
      expect(find.textContaining('response_status'), findsOneWidget);
      expect(find.textContaining('Alice'), findsOneWidget);
      expect(find.textContaining('Bo'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsWidgets);
    });

    test('detail_search finds matches within keys and values of truncated JSON',
        () async {
      const truncatedJson =
          '{"status": "ok", "customers": [{"customer_code": "CUST_999", "tier": "gold';
      final record = RequestRecord(
        id: 'rec_search_trunc_1',
        method: 'GET',
        url: 'https://api.example.com/customers',
        statusCode: 200,
        timestamp: DateTime.now(),
        durationMs: 50,
        requestHeaders: {},
        responseHeaders: {'content-type': 'application/json'},
        responseContentType: 'application/json',
        responseBodyPreview: truncatedJson,
        requestSizeBytes: 0,
        responseSizeBytes: truncatedJson.length,
      );

      final matches = await computeMatchesAsync(record, 'CUST_999', false);
      expect(matches, isNotEmpty);
      expect(
          matches.any((m) => m.section == DetailSection.responseBody), isTrue);

      final tierMatches = await computeMatchesAsync(record, 'gold', false);
      expect(tierMatches, isNotEmpty);
      expect(tierMatches.any((m) => m.section == DetailSection.responseBody),
          isTrue);
    });
  });
}
