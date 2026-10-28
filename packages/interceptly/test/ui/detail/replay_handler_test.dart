import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';
import 'package:interceptly/src/model/request_record.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/ui/detail/replay_handler.dart';
import 'package:interceptly/src/ui/widgets/toast_notification.dart';

import '../../helpers/async_test_utils.dart';
import '../../helpers/mock_http_client.dart';

void main() {
  setUp(() {
    ToastNotification.dispose();
  });

  tearDown(() {
    ToastNotification.dispose();
  });
  group('ReplayHandler data loss awareness', () {
    testWidgets(
      'shows warning toast when replaying request with truncated body (hasDataLoss == true)',
      (tester) async {
        MockHttpClientRequest? capturedRequest;
        final engine = InterceptlyEngine();
        addTearDown(engine.dispose);

        late BuildContext savedContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) {
                savedContext = ctx;
                return const Scaffold(body: SizedBox());
              },
            ),
          ),
        );

        final handler = ReplayHandler(
          context: savedContext,
          engine: engine,
          clientFactory: () => MockHttpClient((req) => capturedRequest = req),
        );

        final record = _record(
          method: 'POST',
          url: 'https://api.example.com/items',
          requestSizeBytes: 4096,
          requestBodyPreview: '{"name":"item1"}',
          requestTruncation: const BodyTruncation(
            originalBytes: 4096,
            retainedBytes: 1024,
            stage: TruncationStage.storage,
          ),
        );

        await tester.runAsync(() async {
          await handler.retry(record,
              confirm: false, allowTruncatedReplay: true);
        });
        await tester.pump();

        expect(capturedRequest, isNotNull);
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'does not show warning toast when replaying request without data loss',
      (tester) async {
        MockHttpClientRequest? capturedRequest;
        final engine = InterceptlyEngine();
        addTearDown(engine.dispose);

        late BuildContext savedContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) {
                savedContext = ctx;
                return const Scaffold(body: SizedBox());
              },
            ),
          ),
        );

        final handler = ReplayHandler(
          context: savedContext,
          engine: engine,
          clientFactory: () => MockHttpClient((req) => capturedRequest = req),
        );

        final record = _record(
          method: 'POST',
          url: 'https://api.example.com/items',
          requestSizeBytes: 100,
          requestBodyPreview: '{"name":"item1"}',
          requestTruncation: const BodyTruncation.complete(100),
        );

        await tester.runAsync(() async {
          await handler.retry(record, confirm: false);
        });
        await tester.pump();

        expect(
          find.text(
            'Warning: Request body was truncated during capture and may be incomplete.',
          ),
          findsNothing,
        );
        expect(capturedRequest, isNotNull);
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'does not show warning toast when replaying request with preview-only truncation',
      (tester) async {
        MockHttpClientRequest? capturedRequest;
        final engine = InterceptlyEngine();
        addTearDown(engine.dispose);

        late BuildContext savedContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) {
                savedContext = ctx;
                return const Scaffold(body: SizedBox());
              },
            ),
          ),
        );

        final handler = ReplayHandler(
          context: savedContext,
          engine: engine,
          clientFactory: () => MockHttpClient((req) => capturedRequest = req),
        );

        final record = _record(
          method: 'POST',
          url: 'https://api.example.com/items',
          requestSizeBytes: 5000,
          requestBodyPreview: '{"name":"item1"}',
          requestTruncation: const BodyTruncation(
            originalBytes: 5000,
            retainedBytes: 500,
            stage: TruncationStage.preview,
          ),
        );

        await tester.runAsync(() async {
          await handler.retry(record, confirm: false);
        });
        await tester.pump();

        expect(
          find.text(
            'Warning: Request body was truncated during capture and may be incomplete.',
          ),
          findsNothing,
        );
        expect(capturedRequest, isNotNull);
        await tester.pump(const Duration(seconds: 3));
      },
    );
  });

  group('Replay redirect and response hardening', () {
    testWidgets('does not follow redirects and captures the 3xx directly',
        (tester) async {
      MockHttpClientRequest? capturedRequest;
      final engine = InterceptlyEngine(
        settings: const InterceptlySettings(persistToDisk: false),
      );
      addTearDown(() => tester.runAsync(engine.dispose));
      await tester.runAsync(engine.initialize);

      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              savedContext = ctx;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );

      final client = MockHttpClient((request) {
        capturedRequest = request;
        request.response = MockHttpClientResponse(statusCode: 302);
        request.response.headers.set(
          'location',
          'http://127.0.0.1/internal-only',
        );
      });
      final handler = ReplayHandler(
        context: savedContext,
        engine: engine,
        clientFactory: () => client,
      );

      final record = _record(url: 'https://api.example.com/redirect');
      await tester.runAsync(() async {
        await handler.retry(record, confirm: false);
        await waitForCondition(() => engine.entries.isNotEmpty);
      });

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.followRedirects, isFalse);
      expect(engine.entries.single.statusCode, equals(302));
      expect(client.closed, isTrue);
      expect(client.forceClosed, isFalse);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('caps streamed response body and preserves true size',
        (tester) async {
      const cap = 10 * 1024 * 1024;
      const chunkSize = 1024 * 1024;
      final chunks = <Uint8List>[
        for (var i = 0; i < 10; i++) Uint8List(chunkSize),
        Uint8List.fromList(const [1]),
      ];
      final totalBytes = cap + 1;

      final engine = InterceptlyEngine(
        settings: const InterceptlySettings(
          persistToDisk: false,
          maxBodyBytes: 20 * 1024 * 1024,
          maxUiPreviewBytes: 20 * 1024 * 1024,
        ),
      );
      addTearDown(() => tester.runAsync(engine.dispose));
      await tester.runAsync(engine.initialize);

      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              savedContext = ctx;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );

      final client = MockHttpClient((request) {
        request.response = MockHttpClientResponse(
          bodyStream: Stream<List<int>>.fromIterable(chunks),
        );
      });
      final handler = ReplayHandler(
        context: savedContext,
        engine: engine,
        clientFactory: () => client,
      );

      final record = _record(url: 'https://api.example.com/large');
      await tester.runAsync(() async {
        await handler.retry(record, confirm: false);
        await waitForCondition(() => engine.entries.isNotEmpty);
      });

      final entry = engine.entries.single;
      expect(entry.responseSizeBytes, equals(totalBytes));
      expect(entry.responseTruncation.stage, equals(TruncationStage.storage));
      expect(entry.responseTruncation.originalBytes, equals(totalBytes));
      expect(entry.responseTruncation.retainedBytes, equals(cap));

      late RequestRecord detail;
      await tester.runAsync(() async {
        detail = await engine.loadDetail(entry);
      });
      expect(detail.responseBodyBytes, isNotNull);
      expect(detail.responseBodyBytes!.length, equals(cap));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('force-closes on stream timeout error and records nothing',
        (tester) async {
      final engine = InterceptlyEngine(
        settings: const InterceptlySettings(persistToDisk: false),
      );
      addTearDown(() => tester.runAsync(engine.dispose));
      await tester.runAsync(engine.initialize);

      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              savedContext = ctx;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );

      final client = MockHttpClient((request) {
        request.response = MockHttpClientResponse(
          bodyStream: Stream<List<int>>.error(
            TimeoutException('response deadline exceeded'),
          ),
        );
      });
      final handler = ReplayHandler(
        context: savedContext,
        engine: engine,
        clientFactory: () => client,
      );

      final record = _record(url: 'https://api.example.com/timeout');
      await tester.runAsync(() async {
        await handler.retry(record, confirm: false);
      });
      await tester.pump();

      expect(client.forceClosed, isTrue);
      expect(engine.entries, isEmpty);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('Replay address guard', () {
    test('blocks mapped private IPv4 and ULA IPv6 addresses', () async {
      for (final host in [
        '::ffff:127.0.0.1',
        '::ffff:10.0.0.1',
        '::ffff:192.168.1.1',
        'fc00::1',
        'fd00::1',
        'fd12::1',
        'fdff::1',
      ]) {
        expect(
          await ReplayHandler.isBlockedHostAsync(host),
          isTrue,
          reason: 'Expected $host to be blocked',
        );
      }
    });

    test('allows mapped public IPv4 and public IPv6 addresses', () async {
      expect(await ReplayHandler.isBlockedHostAsync('::ffff:8.8.8.8'), isFalse);
      expect(
        await ReplayHandler.isBlockedHostAsync('2001:4860:4860::8888'),
        isFalse,
      );
    });
  });

  group('Truncated replay confirmation', () {
    testWidgets('confirming a truncated replay sends the retained body',
        (tester) async {
      MockHttpClientRequest? capturedRequest;
      var confirmationCalls = 0;
      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);

      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              savedContext = ctx;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );

      final handler = ReplayHandler(
        context: savedContext,
        engine: engine,
        clientFactory: () => MockHttpClient(
          (request) => capturedRequest = request,
        ),
        confirmDialog: (context, method) async {
          confirmationCalls++;
          return true;
        },
      );

      final record = _record(
        method: 'POST',
        url: 'https://api.example.com/items',
        requestSizeBytes: 4096,
        requestBodyPreview: '{"name":"item1"}',
        requestTruncation: const BodyTruncation(
          originalBytes: 4096,
          retainedBytes: 1024,
          stage: TruncationStage.storage,
        ),
      );

      await tester.runAsync(() async {
        await handler.retry(record, confirm: true);
      });
      await tester.pump();

      expect(confirmationCalls, equals(1));
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.body, contains('{"name":"item1"}'));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('cancelling a truncated replay sends nothing', (tester) async {
      MockHttpClientRequest? capturedRequest;
      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);

      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              savedContext = ctx;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );

      final handler = ReplayHandler(
        context: savedContext,
        engine: engine,
        clientFactory: () => MockHttpClient(
          (request) => capturedRequest = request,
        ),
        confirmDialog: (context, method) async => false,
      );

      final record = _record(
        method: 'POST',
        url: 'https://api.example.com/items',
        requestSizeBytes: 4096,
        requestBodyPreview: '{"name":"item1"}',
        requestTruncation: const BodyTruncation(
          originalBytes: 4096,
          retainedBytes: 1024,
          stage: TruncationStage.storage,
        ),
      );

      await tester.runAsync(() async {
        await handler.retry(record, confirm: true);
      });
      await tester.pump();

      expect(capturedRequest, isNull);
      await tester.pump(const Duration(seconds: 3));
    });
  });
}

RequestRecord _record({
  String method = 'GET',
  String url = 'https://api.example.com/test',
  int statusCode = 200,
  int requestSizeBytes = 0,
  BodyTruncation requestTruncation = const BodyTruncation.complete(0),
  Map<String, String>? requestHeaders,
  Map<String, String>? responseHeaders,
  String? requestBodyPreview,
  String? responseBodyPreview,
}) {
  return RequestRecord(
    id: 'test-id',
    method: method,
    url: url,
    statusCode: statusCode,
    durationMs: 50,
    requestSizeBytes: requestSizeBytes,
    responseSizeBytes: 0,
    timestamp: DateTime(2026, 1, 1),
    requestHeaders: requestHeaders ?? {},
    responseHeaders: responseHeaders ?? {},
    requestBodyPreview: requestBodyPreview,
    responseBodyPreview: responseBodyPreview,
    requestTruncation: requestTruncation,
  );
}
