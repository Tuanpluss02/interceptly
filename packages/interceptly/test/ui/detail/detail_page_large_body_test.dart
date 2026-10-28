// ignore_for_file: invalid_use_of_internal_member

import 'dart:convert';

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

void main() {
  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

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
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: const BodyTruncation.complete(0),
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

    final engine = InterceptlyEngine();
    final controller = _FakeScopeController(record: record, engine: engine);
    addTearDown(controller.dispose);

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

    /// Large documents flatten off the UI thread behind a spinner,
    /// so allow real async isolates to complete before settling.
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 2)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('URL'), findsOneWidget);

    await tester.tap(find.text('Response'));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 2)));
    await tester.pump(const Duration(seconds: 1));

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
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: const BodyTruncation.complete(0),
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

    final engine = InterceptlyEngine();
    final controller = _FakeScopeController(record: record, engine: engine);
    addTearDown(controller.dispose);

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

    expect(tester.takeException(), isNull);
  });
}
