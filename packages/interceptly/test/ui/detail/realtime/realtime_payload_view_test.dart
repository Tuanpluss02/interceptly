import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/detail/realtime/bounded_lru_cache.dart';
import 'package:interceptly/src/ui/detail/realtime/realtime_payload_view.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';

void main() {
  group('RealtimePayloadView Binary Decoding & Toggle Tests', () {
    testWidgets('binary frame with valid JSON renders JsonViewer and allows Hex toggle',
        (tester) async {
      final jsonBytes = Uint8List.fromList(
        utf8.encode('{"event":"status","online":true}'),
      );
      final frame = RealtimeFrame.binary(
        id: 'frame_bin_json',
        sessionId: 'sess_1',
        direction: FrameDirection.incoming,
        bytes: jsonBytes,
      );

      final cache = BoundedLruCache<String, dynamic>(capacity: 10);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RealtimePayloadView(
              frame: frame,
              isInspected: true,
              parsedJson: null,
              onToggleInspect: () {},
              jsonCache: cache,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should default to decoded mode showing JsonViewer
      expect(find.byType(JsonViewer), findsOneWidget);

      // Toggle buttons exist
      final hexToggle = find.byKey(const ValueKey('frame_toggle_hex_frame_bin_json'));
      final decodedToggle =
          find.byKey(const ValueKey('frame_toggle_decoded_frame_bin_json'));
      expect(hexToggle, findsOneWidget);
      expect(decodedToggle, findsOneWidget);

      // Switch to Hex
      await tester.tap(hexToggle);
      await tester.pumpAndSettle();

      expect(find.byType(JsonViewer), findsNothing);
      expect(find.textContaining('[binary:'), findsOneWidget);

      // Switch back to Decoded (JSON)
      await tester.tap(decodedToggle);
      await tester.pumpAndSettle();

      expect(find.byType(JsonViewer), findsOneWidget);
    });

    testWidgets('binary frame with plain text displays text and allows Hex toggle',
        (tester) async {
      final textBytes = Uint8List.fromList(
        utf8.encode('Plain WebSocket text inside binary frame'),
      );
      final frame = RealtimeFrame.binary(
        id: 'frame_bin_text',
        sessionId: 'sess_1',
        direction: FrameDirection.outgoing,
        bytes: textBytes,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RealtimePayloadView(
              frame: frame,
              isInspected: true,
              parsedJson: null,
              onToggleInspect: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Plain WebSocket text inside binary frame'), findsOneWidget);
      final hexToggle = find.byKey(const ValueKey('frame_toggle_hex_frame_bin_text'));
      expect(hexToggle, findsOneWidget);

      await tester.tap(hexToggle);
      await tester.pumpAndSettle();

      expect(find.textContaining('[binary:'), findsOneWidget);
    });

    testWidgets('raw un-decodable binary frame shows hex only without toggle buttons',
        (tester) async {
      final rawBytes = Uint8List.fromList([0x00, 0x01, 0xFF, 0xFE, 0x02]);
      final frame = RealtimeFrame.binary(
        id: 'frame_raw_bin',
        sessionId: 'sess_1',
        direction: FrameDirection.incoming,
        bytes: rawBytes,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RealtimePayloadView(
              frame: frame,
              isInspected: true,
              parsedJson: null,
              onToggleInspect: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('[binary: 5 bytes]'), findsOneWidget);
      expect(find.byKey(const ValueKey('frame_toggle_hex_frame_raw_bin')),
          findsNothing);
      expect(find.byKey(const ValueKey('frame_toggle_decoded_frame_raw_bin')),
          findsNothing);
    });
  });
}
