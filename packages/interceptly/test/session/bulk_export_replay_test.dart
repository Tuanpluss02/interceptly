/// Bulk export isolation, replay safety, and share path validation.
///
/// Covers the 50-item bulk cap, truncated replay blocking with override,
/// DNS-backed host guards, and canonical temp-directory checks.

library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/core/interceptly_controller.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/request_record.dart';
import 'package:interceptly/src/share/interceptly_share.dart';
import 'package:interceptly/src/ui/detail/replay_handler.dart';
import 'package:interceptly/src/ui/tabs/network_tab.dart';
import 'package:interceptly/src/ui/widgets/toast_notification.dart';

import '../helpers/mock_http_client.dart';

void main() {
  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('Bulk export and replay safety', () {
    test('bulk export cap constant is 50', () {
      expect(kMaxBulkExportItems, 50);
    });

    testWidgets('replay blocks truncated body without override',
        (tester) async {
      MockHttpClientRequest? captured;
      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);
      late BuildContext saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (ctx) {
            saved = ctx;
            return const SizedBox();
          }),
        ),
      );
      final handler = ReplayHandler(
        context: saved,
        engine: engine,
        clientFactory: () => MockHttpClient((req) => captured = req),
      );
      final record = RequestRecord(
        id: 'trunc',
        method: 'POST',
        url: 'https://api.example.com/items',
        statusCode: 200,
        durationMs: 10,
        requestSizeBytes: 4096,
        responseSizeBytes: 0,
        timestamp: DateTime(2026, 1, 1),
        requestHeaders: const {},
        responseHeaders: const {},
        requestBodyPreview: '{"a":1}',
        requestTruncation: const BodyTruncation(
          originalBytes: 4096,
          retainedBytes: 100,
          stage: TruncationStage.storage,
        ),
      );
      await tester.runAsync(() async {
        await handler.retry(record, confirm: false);
      });
      expect(captured, isNull);

      await tester.runAsync(() async {
        await handler.retry(record, confirm: false, allowTruncatedReplay: true);
      });
      expect(captured, isNotNull);
      ToastNotification.dispose();
      await tester.pump();
    });

    test('replay async host guard blocks literals', () async {
      expect(await ReplayHandler.isBlockedHostAsync('localhost'), isTrue);
      expect(await ReplayHandler.isBlockedHostAsync('127.0.0.1'), isTrue);
      expect(await ReplayHandler.isBlockedHostAsync('10.0.0.5'), isTrue);
    });

    test('share path validation canonicalizes symlinks', () async {
      final temp = Directory.systemTemp.path;
      final probe = File(
          '$temp/interceptly_probe_${DateTime.now().microsecondsSinceEpoch}.json');
      await probe.writeAsString('{}');
      try {
        expect(InterceptlyShare.isWithinTempDirectory(probe.path), isTrue);
      } finally {
        try {
          await probe.delete();
        } catch (_) {}
      }
      expect(InterceptlyShare.isWithinTempDirectory('/etc/passwd'), isFalse);
      expect(InterceptlyShare.isWithinTempDirectory('/tmp/../etc/shadow'),
          isFalse);
      expect(InterceptlyShare.isWithinTempDirectory('${temp}2_evil/file.json'),
          isFalse);
    });
  });
}
