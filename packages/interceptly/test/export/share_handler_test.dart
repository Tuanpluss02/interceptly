import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/request_record.dart';
import 'package:interceptly/src/share/interceptly_share.dart';
import 'package:interceptly/src/ui/detail/share_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('share_handler_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
      if (call.method == 'getTemporaryDirectory') {
        return tempDir.path;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets(
    'ShareHandler defaults to redactOnExport true',
    (tester) async {
      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              savedContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(
        ShareHandler(context: savedContext, fabKey: GlobalKey())
            .redactOnExport,
        isTrue,
      );
      expect(
        ShareHandler.withShare(
          context: savedContext,
          fabKey: GlobalKey(),
          share: _NeverShare(),
        ).redactOnExport,
        isTrue,
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'share fallback does not copy file path',
    (tester) async {
      late BuildContext savedContext;
      final fabKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: FloatingActionButton(
              key: fabKey,
              onPressed: () {},
            ),
            body: Builder(
              builder: (ctx) {
                savedContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final clipboardTexts = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<dynamic, dynamic>?;
          clipboardTexts.add((args?['text'] ?? '').toString());
        }
        return null;
      });

      final handler = ShareHandler.withShare(
        context: savedContext,
        fabKey: fabKey,
        share: _NeverShare(),
      );

      await tester.runAsync(() async {
        await handler.exportHarFile(_record());
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      for (final text in clipboardTexts) {
        expect(text, isNot(contains(tempDir.path)));
        expect(text, isNot(contains('.har')));
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'share fallback does not copy file path for Postman export',
    (tester) async {
      late BuildContext savedContext;
      final fabKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: FloatingActionButton(
              key: fabKey,
              onPressed: () {},
            ),
            body: Builder(
              builder: (ctx) {
                savedContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final clipboardTexts = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<dynamic, dynamic>?;
          clipboardTexts.add((args?['text'] ?? '').toString());
        }
        return null;
      });

      final handler = ShareHandler.withShare(
        context: savedContext,
        fabKey: fabKey,
        share: _NeverShare(),
      );

      await tester.runAsync(() async {
        await handler.exportPostmanRecords([_record()]);
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      for (final text in clipboardTexts) {
        expect(text, isNot(contains(tempDir.path)));
        expect(text, isNot(contains('.postman_collection')));
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

class _NeverShare extends Fake implements InterceptlyShare {
  @override
  Future<bool> shareFile({
    required String filePath,
    String? subject,
    String? text,
    String? mimeType,
    Rect? origin,
    int maxFileSizeBytes = 50 * 1024 * 1024,
  }) async {
    return false;
  }
}

RequestRecord _record() {
  return RequestRecord(
    id: 'test-id',
    method: 'GET',
    url: 'https://api.example.com/test',
    statusCode: 200,
    durationMs: 50,
    requestSizeBytes: 0,
    responseSizeBytes: 0,
    timestamp: DateTime(2026, 1, 1),
    requestHeaders: const {},
    responseHeaders: const {},
    requestTruncation: const BodyTruncation.complete(0),
    responseTruncation: const BodyTruncation.complete(0),
  );
}
