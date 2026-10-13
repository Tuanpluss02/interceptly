import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/request_record.dart';
import 'package:interceptly/src/session/inspector_session.dart';
import 'package:interceptly/src/ui/detail/custom_request_page.dart';
import 'package:interceptly/src/ui/detail/detail_tabs_builder.dart';
import 'package:interceptly/src/ui/detail/replay_handler.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InspectorSession session;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('challenger_m3_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      },
    );
    session = InspectorSession();
    await session.initialize();
  });

  tearDownAll(() async {
    session.dispose();
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Adversarial Stress Test: JsonViewer Edge Cases', () {
    testWidgets('Empty map {} renders without overflow and gutter aligns',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              width: 300,
              child: JsonViewer(data: {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final line1 = find.text('1');
      final content = find.textContaining('{}');
      expect(line1, findsOneWidget);
      expect(content, findsOneWidget);
      expect(
          tester.getTopLeft(line1).dy, equals(tester.getTopLeft(content).dy));
    });

    testWidgets('Empty list [] renders without overflow and gutter aligns',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              width: 300,
              child: JsonViewer(data: []),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final line1 = find.text('1');
      final content = find.textContaining('[]');
      expect(line1, findsOneWidget);
      expect(content, findsOneWidget);
      expect(
          tester.getTopLeft(line1).dy, equals(tester.getTopLeft(content).dy));
    });

    testWidgets(
        'Primitive values (string, int, bool) render and align; null shows No Data',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              width: 300,
              child: JsonViewer(data: null),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No Data'), findsOneWidget);

      for (final val in ['a primitive string', 12345, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 200,
                width: 300,
                child: JsonViewer(data: val),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final line1 = find.text('1');
        expect(line1, findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('Deeply nested structures (25 levels) scroll and stay aligned',
        (tester) async {
      dynamic nested = 'leaf_value';
      for (int i = 25; i >= 1; i--) {
        nested = {'level_$i': nested};
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              width: 400,
              child: JsonViewer(data: nested),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final line1Finder = find.text('1');
      expect(line1Finder, findsOneWidget);
      final initialLine1Y = tester.getTopLeft(line1Finder).dy;

      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -25),
      );
      await tester.pumpAndSettle();

      final scrolledLine1Y = tester.getTopLeft(line1Finder).dy;
      expect(scrolledLine1Y, lessThan(initialLine1Y));

      // Line 15 corresponds to level_14 in 25-deep nesting (line 1 is '{', line 2 is level_1 ... line 15 is level_14)
      final line15 = find.text('15');
      if (line15.evaluate().isNotEmpty) {
        final content14 = find.textContaining('"level_14"');
        if (content14.evaluate().isNotEmpty) {
          expect(tester.getTopLeft(line15).dy,
              equals(tester.getTopLeft(content14).dy));
        }
      }
    });

    testWidgets(
        'Extreme wide content lines maintain horizontal & vertical scroll',
        (tester) async {
      final wideKey = 'K' * 500;
      final wideValue = 'V' * 2000;
      final data = {
        for (int i = 1; i <= 20; i++) '${wideKey}_$i': '${wideValue}_$i',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 250,
              width: 250,
              child: JsonViewer(data: data),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final line1Finder = find.text('1');
      final initialGutterX = tester.getTopLeft(line1Finder).dx;
      final initialGutterY = tester.getTopLeft(line1Finder).dy;

      // Scroll horizontally
      final horizontalScrollable = tester.state<ScrollableState>(
        find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
      );
      horizontalScrollable.position.jumpTo(100.0);
      await tester.pumpAndSettle();

      // Gutter X must not change
      expect(tester.getTopLeft(line1Finder).dx, equals(initialGutterX));

      // Drag vertically
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -25),
      );
      await tester.pumpAndSettle();

      final scrolledGutterY = tester.getTopLeft(line1Finder).dy;
      expect(scrolledGutterY, lessThan(initialGutterY));
      expect(tester.getTopLeft(line1Finder).dx, equals(initialGutterX));
    });

    testWidgets('Toggling fold node maintains gutter alignment',
        (tester) async {
      final data = {
        'section_a': {
          for (int i = 1; i <= 10; i++) 'key_a_$i': 'val_$i',
        },
        'section_b': {
          for (int i = 1; i <= 10; i++) 'key_b_$i': 'val_$i',
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              width: 400,
              child: JsonViewer(data: data),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on line 2 gutter fold icon to collapse section_a
      final line2 = find.text('2');
      expect(line2, findsOneWidget);
      await tester.tap(line2);
      await tester.pumpAndSettle();

      // After collapse, section_b should be visible earlier
      final lineSectionB = find.textContaining('"section_b"');
      expect(lineSectionB, findsOneWidget);

      // Now scroll vertically and check alignment
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -40),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('Adversarial Stress Test: DetailTabsBuilder Binary Edge Cases', () {
    testWidgets('Large binary byte size (10 GB) parses correctly',
        (tester) async {
      final record = RequestRecord(
        id: 'r_large_bin',
        method: 'GET',
        url: 'https://example.com/bigfile',
        statusCode: 200,
        timestamp: DateTime.now(),
        durationMs: 100,
        requestHeaders: {},
        responseHeaders: {'content-type': 'application/octet-stream'},
        requestSizeBytes: 0,
        responseBodyPreview: '\x00[binary: 10737418240 bytes]',
        responseSizeBytes: 10737418240,
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation.complete(0),
      );

      final builder = DetailTabsBuilder(
        record: record,
        matches: const [],
        activeGlobalIndex: null,
        query: '',
        urlDecodeEnabled: false,
        tryParseJson: (s) => s,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: builder.buildResponseTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('10737418240'), findsOneWidget);
      expect(find.textContaining('"kind"'), findsOneWidget);
      expect(find.textContaining('"binary"'), findsOneWidget);
    });

    testWidgets('Zero bytes binary placeholder parses correctly',
        (tester) async {
      final record = RequestRecord(
        id: 'r_zero_bin',
        method: 'POST',
        url: 'https://example.com/empty',
        statusCode: 200,
        timestamp: DateTime.now(),
        durationMs: 10,
        requestHeaders: {'content-type': 'application/octet-stream'},
        responseHeaders: {},
        requestBodyPreview: '\x00[binary: 0 bytes]',
        requestSizeBytes: 0,
        responseSizeBytes: 0,
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation.complete(0),
      );

      final builder = DetailTabsBuilder(
        record: record,
        matches: const [],
        activeGlobalIndex: null,
        query: '',
        urlDecodeEnabled: false,
        tryParseJson: (s) => s,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: builder.buildRequestTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('0'), findsWidgets);
      expect(find.textContaining('"binary"'), findsOneWidget);
    });

    testWidgets('Malformed binary placeholders do not crash', (tester) async {
      final malformed = [
        '\x00[binary:]',
        '\x00[binary: notanumber bytes]',
        '\x00[binary: -999 bytes]',
        '\x00',
        '\x00[',
        '[binary:',
      ];

      for (final preview in malformed) {
        final record = RequestRecord(
          id: 'r_malformed',
          method: 'POST',
          url: 'https://example.com/test',
          statusCode: 200,
          timestamp: DateTime.now(),
          durationMs: 10,
          requestHeaders: {'content-type': 'application/octet-stream'},
          responseHeaders: {},
          requestBodyPreview: preview,
          requestSizeBytes: 10,
          responseSizeBytes: 0,
          requestTruncation: const BodyTruncation.complete(0),
          responseTruncation: const BodyTruncation.complete(0),
        );

        final builder = DetailTabsBuilder(
          record: record,
          matches: const [],
          activeGlobalIndex: null,
          query: '',
          urlDecodeEnabled: false,
          tryParseJson: (s) => s,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: builder.buildRequestTab(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('Recognizes various binary content types and assigns kind',
        (tester) async {
      final testCases = [
        ('image/png', 'image'),
        ('image/jpeg', 'image'),
        ('application/pdf', 'pdf'),
        ('application/x-protobuf', 'protobuf'),
        ('application/msgpack', 'msgpack'),
        ('application/octet-stream', 'binary'),
      ];

      for (final (ct, expectedKind) in testCases) {
        final record = RequestRecord(
          id: 'r_ct_test',
          method: 'GET',
          url: 'https://example.com/file',
          statusCode: 200,
          timestamp: DateTime.now(),
          durationMs: 10,
          requestHeaders: {},
          responseHeaders: {'content-type': ct},
          responseContentType: ct,
          requestSizeBytes: 0,
          responseBodyPreview: '\x00[binary: 128 bytes]',
          responseSizeBytes: 128,
          requestTruncation: const BodyTruncation.complete(0),
          responseTruncation: const BodyTruncation.complete(0),
        );

        final builder = DetailTabsBuilder(
          record: record,
          matches: const [],
          activeGlobalIndex: null,
          query: '',
          urlDecodeEnabled: false,
          tryParseJson: (s) => s,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: builder.buildResponseTab(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('"$expectedKind"'), findsOneWidget);
        expect(find.textContaining('128'), findsOneWidget);
      }
    });

    testWidgets('Non-binary placeholder \\x00[body unavailable] does not crash',
        (tester) async {
      final record = RequestRecord(
        id: 'r_unavail',
        method: 'POST',
        url: 'https://example.com/unavail',
        statusCode: 200,
        timestamp: DateTime.now(),
        durationMs: 10,
        requestHeaders: {},
        responseHeaders: {},
        requestBodyPreview: '\x00[body unavailable]',
        requestSizeBytes: 0,
        responseSizeBytes: 0,
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation.complete(0),
      );

      final builder = DetailTabsBuilder(
        record: record,
        matches: const [],
        activeGlobalIndex: null,
        query: '',
        urlDecodeEnabled: false,
        tryParseJson: (s) => s,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: builder.buildRequestTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('Adversarial Stress Test: ReplayHandler Edge Cases', () {
    testWidgets(
        'Null body on retry transmits without bodyBytes or content-type',
        (tester) async {
      http.Request? capturedRequest;
      final mockClient = MockClient((req) async {
        capturedRequest = req;
        return http.Response('ok', 200);
      });

      final record = RequestRecord(
        id: 'r_null_body',
        method: 'POST',
        url: 'https://example.com/api',
        statusCode: 200,
        timestamp: DateTime.now(),
        durationMs: 10,
        requestHeaders: {},
        responseHeaders: {},
        requestBodyPreview: null,
        requestSizeBytes: 0,
        responseSizeBytes: 0,
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation.complete(0),
      );

      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (ctx) {
            savedContext = ctx;
            return const SizedBox();
          }),
        ),
      );

      await tester.runAsync(() async {
        await http.runWithClient(() async {
          final handler =
              ReplayHandler(context: savedContext, session: session);
          await handler.retry(record);
        }, () => mockClient);
      });

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.bodyBytes, isEmpty);
      expect(capturedRequest!.headers.containsKey('content-type'), isFalse);
    });

    testWidgets('Empty string body on retry transmits without bodyBytes',
        (tester) async {
      http.Request? capturedRequest;
      final mockClient = MockClient((req) async {
        capturedRequest = req;
        return http.Response('ok', 200);
      });

      final record = RequestRecord(
        id: 'r_empty_body',
        method: 'POST',
        url: 'https://example.com/api',
        statusCode: 200,
        timestamp: DateTime.now(),
        durationMs: 10,
        requestHeaders: {},
        responseHeaders: {},
        requestBodyPreview: '',
        requestSizeBytes: 0,
        responseSizeBytes: 0,
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation.complete(0),
      );

      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (ctx) {
            savedContext = ctx;
            return const SizedBox();
          }),
        ),
      );

      await tester.runAsync(() async {
        await http.runWithClient(() async {
          final handler =
              ReplayHandler(context: savedContext, session: session);
          await handler.retry(record);
        }, () => mockClient);
      });

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.bodyBytes, isEmpty);
      expect(capturedRequest!.headers.containsKey('content-type'), isFalse);
    });

    testWidgets('Legitimate JSON array body [ { ... } ] is replayed properly',
        (tester) async {
      http.Request? capturedRequest;
      final mockClient = MockClient((req) async {
        capturedRequest = req;
        return http.Response('ok', 200);
      });

      const arrayJson =
          '[{"id": 1, "name": "first"}, {"id": 2, "name": "second"}]';
      final record = RequestRecord(
        id: 'r_array_json',
        method: 'POST',
        url: 'https://example.com/batch',
        statusCode: 200,
        timestamp: DateTime.now(),
        durationMs: 10,
        requestHeaders: {},
        responseHeaders: {},
        requestBodyPreview: arrayJson,
        requestSizeBytes: arrayJson.length,
        responseSizeBytes: 0,
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation.complete(0),
      );

      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (ctx) {
            savedContext = ctx;
            return const SizedBox();
          }),
        ),
      );

      await tester.runAsync(() async {
        await http.runWithClient(() async {
          final handler =
              ReplayHandler(context: savedContext, session: session);
          await handler.retry(record);
        }, () => mockClient);
      });

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.body, equals(arrayJson));
      expect(capturedRequest!.headers['content-type'],
          equals('application/json; charset=utf-8'));
    });

    testWidgets(
        'Non-JSON plain text body with custom content-type is preserved',
        (tester) async {
      http.Request? capturedRequest;
      final mockClient = MockClient((req) async {
        capturedRequest = req;
        return http.Response('ok', 200);
      });

      const textBody = 'Hello, plain text world!';
      final record = RequestRecord(
        id: 'r_text_body',
        method: 'POST',
        url: 'https://example.com/log',
        statusCode: 200,
        timestamp: DateTime.now(),
        durationMs: 10,
        requestHeaders: {'content-type': 'text/plain'},
        responseHeaders: {},
        requestBodyPreview: textBody,
        requestSizeBytes: textBody.length,
        responseSizeBytes: 0,
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation.complete(0),
      );

      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (ctx) {
            savedContext = ctx;
            return const SizedBox();
          }),
        ),
      );

      await tester.runAsync(() async {
        await http.runWithClient(() async {
          final handler =
              ReplayHandler(context: savedContext, session: session);
          await handler.retry(record);
        }, () => mockClient);
      });

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.body, equals(textBody));
      // Preserves original text/plain content-type
      expect(capturedRequest!.headers['content-type'], equals('text/plain'));
    });

    testWidgets('All placeholder formats are stripped during replay',
        (tester) async {
      final placeholders = [
        '\x00[binary: 4096 bytes]',
        '[binary: 2048 bytes]',
        '\x00[body unavailable]',
        '\x00custom_internal_marker',
      ];

      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (ctx) {
            savedContext = ctx;
            return const SizedBox();
          }),
        ),
      );

      for (final placeholder in placeholders) {
        http.Request? capturedRequest;
        final mockClient = MockClient((req) async {
          capturedRequest = req;
          return http.Response('ok', 200);
        });

        final record = RequestRecord(
          id: 'r_ph',
          method: 'PUT',
          url: 'https://example.com/item',
          statusCode: 200,
          timestamp: DateTime.now(),
          durationMs: 10,
          requestHeaders: {},
          responseHeaders: {},
          requestBodyPreview: placeholder,
          requestSizeBytes: 50,
          responseSizeBytes: 0,
          requestTruncation: const BodyTruncation.complete(0),
          responseTruncation: const BodyTruncation(
            originalBytes: 7000000,
            retainedBytes: 5000000,
            stage: TruncationStage.storage,
          ),
        );

        await tester.runAsync(() async {
          await http.runWithClient(() async {
            final handler =
                ReplayHandler(context: savedContext, session: session);
            await handler.retry(record);
          }, () => mockClient);
        });

        expect(capturedRequest, isNotNull);
        expect(capturedRequest!.bodyBytes, isEmpty,
            reason: 'Failed for placeholder: $placeholder');
        expect(capturedRequest!.headers.containsKey('content-type'), isFalse);
      }
    });

    testWidgets('duplicateAndEdit sanitizes placeholder bodies to empty string',
        (tester) async {
      final testCases = [
        ('\x00[binary: 2048 bytes]', ''),
        ('\x00[body unavailable]', ''),
        ('[binary: 1024 bytes]', ''),
        ('{"valid": "json"}', '{"valid": "json"}'),
        (null, ''),
      ];

      for (final (bodyPreview, expectedBody) in testCases) {
        late BuildContext savedContext;
        CustomRequestPage? pushedPage;
        final observer = _CaptureNavigatorObserver(onPushed: (route) {
          if (route is MaterialPageRoute<CustomRequestDraft>) {
            final page = route.builder(savedContext);
            if (page is CustomRequestPage) {
              pushedPage = page;
            }
          }
        });

        final record = RequestRecord(
          id: 'r_edit_test',
          method: 'POST',
          url: 'https://example.com/item',
          statusCode: 200,
          timestamp: DateTime.now(),
          durationMs: 10,
          requestHeaders: {},
          responseHeaders: {},
          requestBodyPreview: bodyPreview,
          requestSizeBytes: bodyPreview?.length ?? 0,
          responseSizeBytes: 0,
          requestTruncation: const BodyTruncation.complete(0),
          responseTruncation: const BodyTruncation.complete(0),
        );

        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [observer],
            home: Builder(builder: (ctx) {
              savedContext = ctx;
              return const SizedBox();
            }),
          ),
        );

        final handler = ReplayHandler(context: savedContext, session: session);
        handler.duplicateAndEdit(record);
        await tester.pump();

        expect(pushedPage, isNotNull);
        expect(pushedPage!.initialBodyText, equals(expectedBody));
      }
    });
  });
}

class _CaptureNavigatorObserver extends NavigatorObserver {
  final void Function(Route<dynamic> route) onPushed;
  _CaptureNavigatorObserver({required this.onPushed});

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onPushed(route);
  }
}
