import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/request_record.dart';
import 'package:interceptly/src/session/inspector_session.dart';
import 'package:interceptly/src/ui/detail/replay_handler.dart';

import '../helpers/mock_http_client.dart';

void main() {
  group('ReplayHandler data loss awareness', () {
    testWidgets(
      'shows warning toast when replaying request with truncated body (hasDataLoss == true)',
      (tester) async {
        MockHttpClientRequest? capturedRequest;
        final session = InspectorSession();
        addTearDown(session.dispose);

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
          session: session,
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
          await handler.retry(record, confirm: false);
        });
        await tester.pump();

        expect(
          find.text(
            'Warning: Request body was truncated during capture and may be incomplete.',
          ),
          findsOneWidget,
        );
        expect(capturedRequest, isNotNull);
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'does not show warning toast when replaying request without data loss',
      (tester) async {
        MockHttpClientRequest? capturedRequest;
        final session = InspectorSession();
        addTearDown(session.dispose);

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
          session: session,
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
        final session = InspectorSession();
        addTearDown(session.dispose);

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
          session: session,
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
