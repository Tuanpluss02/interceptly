// ignore_for_file: invalid_use_of_internal_member

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';

void main() {
  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  testWidgets('detail page opens file-backed large JSON without throwing',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') {
          return Directory.systemTemp.path;
        }
        return null;
      },
    );

    final items = List.generate(
      1500,
      (i) => {'id': i, 'name': 'item number $i with padding text'},
    );
    final bigJson = jsonEncode({'data': items});
    expect(bigJson.length, greaterThan(50 * 1024));

    final engine = InterceptlyEngine();
    await tester.runAsync(() async {
      await engine.initialize();
      engine.record(
        RawCapture(
          id: 'r1',
          method: 'POST',
          url: 'https://api.example.com/data',
          requestHeaders: const {'content-type': 'application/json'},
          responseHeaders: const {'content-type': 'application/json'},
          statusCode: 200,
          durationMs: 12,
          timestamp: DateTime.now(),
          requestBodyBytes: RawCapture.wrapBytes(
            Uint8List.fromList(utf8.encode('{"q":1}')),
          ),
          responseBodyBytes: RawCapture.wrapBytes(
            Uint8List.fromList(utf8.encode(bigJson)),
          ),
          requestContentType: 'application/json',
          responseContentType: 'application/json',
        ),
      );

      final end = DateTime.now().add(const Duration(seconds: 15));
      while (engine.entries.isEmpty) {
        if (DateTime.now().isAfter(end)) {
          throw StateError('entries never arrived');
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });

    final controller = InterceptlyScopeController(engine: engine);
    addTearDown(() async {
      controller.dispose();
      await engine.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: InterceptlyScope(
          controller: controller,
          child: RequestDetailPage(
            entry: engine.entries.first,
          ),
        ),
      ),
    );
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('URL').evaluate().isNotEmpty) break;
    }
    expect(tester.takeException(), isNull);
    expect(find.text('URL'), findsOneWidget);

    await tester.tap(find.text('Response'));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('RESPONSE BODY').evaluate().isNotEmpty) break;
    }
    expect(tester.takeException(), isNull);
    expect(find.text('RESPONSE BODY'), findsOneWidget);
  });
}
