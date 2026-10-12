import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interceptly/src/model/request_record.dart';
import 'package:interceptly/src/session/inspector_session.dart';
import 'package:interceptly/src/ui/detail/detail_tabs_builder.dart';
import 'package:interceptly/src/ui/detail/replay_handler.dart';
import 'package:interceptly/src/ui/widgets/json_viewer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JsonViewer vertical scroll synchronization', () {
    testWidgets(
      'synchronizes line number gutter with vertical scrollable content',
      (tester) async {
        final data = [
          for (int i = 1; i <= 20; i++)
            {
              'index': i,
              'label': 'item_$i',
            },
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 250,
                width: 400,
                child: JsonViewer(data: data),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Initial positions: line number '1' and content '[' must be aligned
        final line1Finder = find.text('1');
        final contentLine1Finder = find.textContaining('[');
        expect(line1Finder, findsOneWidget);
        expect(contentLine1Finder, findsWidgets);

        final initialLine1Y = tester.getTopLeft(line1Finder).dy;
        final initialContentY = tester.getTopLeft(contentLine1Finder.first).dy;
        expect(initialLine1Y, equals(initialContentY));

        // 2. Perform vertical scroll by dragging SingleChildScrollView
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -25),
        );
        await tester.pumpAndSettle();

        // 3. Verify that line 1 has scrolled up and gutter moved in sync
        final scrolledLine1Y = tester.getTopLeft(line1Finder).dy;
        final scrolledContentY = tester.getTopLeft(contentLine1Finder.first).dy;

        expect(scrolledLine1Y, lessThan(initialLine1Y));
        expect(scrolledLine1Y, equals(scrolledContentY));

        // 4. Check another line (e.g. line 12) to verify continued gutter and content alignment
        final line12Finder = find.text('12');
        expect(line12Finder, findsOneWidget);
        final line12Y = tester.getTopLeft(line12Finder).dy;

        final itemFinder = find.textContaining('"item_3"');
        expect(itemFinder, findsOneWidget);
        final itemY = tester.getTopLeft(itemFinder).dy;

        expect(line12Y, equals(itemY));
      },
    );

    testWidgets(
        'horizontal scroll keeps gutter line numbers docked to the left edge',
        (tester) async {
      final data = {
        'very_long_nested_key_to_force_horizontal_scrolling_beyond_viewport_width':
            'very_long_nested_value_that_is_wide_enough_to_exceed_narrow_container_width',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 250,
              width: 200,
              child: JsonViewer(data: data),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final line1Finder = find.text('1');
      expect(line1Finder, findsOneWidget);
      final initialGutterX = tester.getTopLeft(line1Finder).dx;

      final textFinder = find.textContaining('very_long_nested_key');
      expect(textFinder, findsOneWidget);
      final initialTextX = tester.getTopLeft(textFinder).dx;

      // Jump horizontal scroll position by 50px
      final horizontalScrollable = tester.state<ScrollableState>(
        find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
      );
      horizontalScrollable.position.jumpTo(50.0);
      await tester.pumpAndSettle();

      final scrolledGutterX = tester.getTopLeft(line1Finder).dx;
      final scrolledTextX = tester.getTopLeft(textFinder).dx;

      // Gutter must remain pinned/docked horizontally
      expect(scrolledGutterX, equals(initialGutterX));
      // Content text must have scrolled to the left
      expect(scrolledTextX, equals(initialTextX - 50.0));
    });

    testWidgets(
        'fold indicators scroll vertically with the lines they represent',
        (tester) async {
      final data = {
        for (int i = 1; i <= 15; i++)
          'nested_obj_$i': {
            'child_a': i,
            'child_b': 'val_$i',
          },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 250,
              width: 400,
              child: JsonViewer(data: data),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Line 2 has 'nested_obj_1' which is an object with fold arrow
      final line2Finder = find.text('2');
      final contentLine2Finder = find.textContaining('"nested_obj_1"');
      expect(line2Finder, findsOneWidget);
      expect(contentLine2Finder, findsOneWidget);
      final initialLine2Y = tester.getTopLeft(line2Finder).dy;
      expect(initialLine2Y, equals(tester.getTopLeft(contentLine2Finder).dy));

      // Drag up by 50px using vertical SingleChildScrollView
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -50),
      );
      await tester.pumpAndSettle();

      final scrolledLine2Y = tester.getTopLeft(line2Finder).dy;
      final scrolledContent2Y = tester.getTopLeft(contentLine2Finder).dy;

      // Both gutter and content for line 2 must move up together
      expect(scrolledLine2Y, lessThan(initialLine2Y));
      expect(scrolledLine2Y, equals(scrolledContent2Y));
    });
  });

  group('DetailTabsBuilder binary payload detection', () {
    testWidgets('recognizes \\x00-prefixed binary placeholder', (tester) async {
      final record = RequestRecord(
        id: 'r_bin',
        method: 'POST',
        url: 'https://example.com/upload',
        statusCode: 200,
        timestamp: DateTime.now(),
        durationMs: 50,
        requestHeaders: {'content-type': 'application/octet-stream'},
        responseHeaders: {'content-type': 'application/octet-stream'},
        requestBodyPreview: '\x00[binary: 2048 bytes]',
        responseBodyPreview: '\x00[binary: 4096 bytes]',
        requestSizeBytes: 2048,
        responseSizeBytes: 4096,
        isBodyTruncated: false,
      );

      final builder = DetailTabsBuilder(
        record: record,
        matches: const [],
        activeGlobalIndex: null,
        query: '',
        urlDecodeEnabled: false,
        tryParseJson: (str) {
          if (str == null) return null;
          try {
            return jsonDecode(str);
          } catch (_) {
            return str;
          }
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: builder.buildRequestTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Structured binary metadata rendered
      expect(find.textContaining('"kind"'), findsOneWidget);
      expect(find.textContaining('"binary"'), findsOneWidget);
      expect(find.textContaining('2048'), findsOneWidget);
      // Raw corrupted placeholder string should NOT be displayed as body text
      expect(find.text('\x00[binary: 2048 bytes]'), findsNothing);
    });

    testWidgets('recognizes [binary: ... bytes] placeholder without \\x00',
        (tester) async {
      final record = RequestRecord(
        id: 'r_bin_no_null',
        method: 'POST',
        url: 'https://example.com/data',
        statusCode: 200,
        timestamp: DateTime.now(),
        durationMs: 30,
        requestHeaders: {'content-type': 'application/octet-stream'},
        responseHeaders: {},
        requestBodyPreview: '[binary: 1024 bytes]',
        requestSizeBytes: 1024,
        responseSizeBytes: 0,
        isBodyTruncated: false,
      );

      final builder = DetailTabsBuilder(
        record: record,
        matches: const [],
        activeGlobalIndex: null,
        query: '',
        urlDecodeEnabled: false,
        tryParseJson: (str) => str,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: builder.buildRequestTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('"kind"'), findsOneWidget);
      expect(find.textContaining('1024'), findsOneWidget);
    });
  });

  group('ReplayHandler placeholder guard', () {
    late Directory tempDir;
    late InspectorSession session;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('interceptly_replay_test');
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

    tearDown(() async {
      session.dispose();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    testWidgets(
      'guards against sending placeholder string as HTTP body on retry',
      (tester) async {
        http.Request? capturedRequest;
        final mockClient = MockClient((request) async {
          capturedRequest = request;
          return http.Response('ok', 200);
        });

        final record = RequestRecord(
          id: 'r_replay_bin',
          method: 'POST',
          url: 'https://api.example.com/binary-endpoint',
          statusCode: 200,
          timestamp: DateTime.now(),
          durationMs: 15,
          requestHeaders: {'accept': 'application/json'},
          responseHeaders: {},
          requestBodyPreview: '\x00[binary: 512 bytes]',
          requestSizeBytes: 512,
          responseSizeBytes: 0,
          isBodyTruncated: false,
        );

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

        await tester.runAsync(() async {
          await http.runWithClient(() async {
            final handler =
                ReplayHandler(context: savedContext, session: session);
            await handler.retry(record);
          }, () => mockClient);
        });

        expect(capturedRequest, isNotNull);
        expect(capturedRequest!.bodyBytes, isEmpty);
        expect(capturedRequest!.body, isEmpty);
        expect(capturedRequest!.headers.containsKey('content-type'), isFalse);
      },
    );

    testWidgets('sends legitimate request body normally on retry',
        (tester) async {
      http.Request? capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response('{"success": true}', 200);
      });

      const validJsonBody = '{"user": "alice", "active": true}';
      final record = RequestRecord(
        id: 'r_replay_valid',
        method: 'POST',
        url: 'https://api.example.com/user',
        statusCode: 200,
        timestamp: DateTime.now(),
        durationMs: 20,
        requestHeaders: {'authorization': 'Bearer token123'},
        responseHeaders: {},
        requestBodyPreview: validJsonBody,
        requestSizeBytes: validJsonBody.length,
        responseSizeBytes: 18,
        isBodyTruncated: false,
      );

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

      await tester.runAsync(() async {
        await http.runWithClient(() async {
          final handler =
              ReplayHandler(context: savedContext, session: session);
          await handler.retry(record);
        }, () => mockClient);
      });

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.body, equals(validJsonBody));
      expect(
        capturedRequest!.headers['content-type'],
        equals('application/json; charset=utf-8'),
      );
    });
  });
}
