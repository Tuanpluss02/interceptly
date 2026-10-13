import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JsonViewer Scrollbar tests', () {
    testWidgets('JsonViewer embeds vertical and horizontal Scrollbar widgets',
        (tester) async {
      final sampleData = <String, dynamic>{
        for (int i = 0; i < 50; i++)
          'key_$i': 'value_$i with extra length for line width',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: JsonViewer(
                data: sampleData,
                thumbVisibility: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollbars = find.byType(Scrollbar);
      expect(scrollbars, findsNWidgets(2));

      final jvState = tester.state(find.byType(JsonViewer)) as dynamic;
      final vCtrl = jvState.contentScrollControllerForTest as ScrollController;
      final hCtrl =
          jvState.horizontalScrollControllerForTest as ScrollController;

      final scrollbarWidgets =
          tester.widgetList<Scrollbar>(scrollbars).toList();
      final verticalBar = scrollbarWidgets.firstWhere(
        (sb) => sb.controller == vCtrl,
      );
      final horizontalBar = scrollbarWidgets.firstWhere(
        (sb) => sb.controller == hCtrl,
      );

      expect(verticalBar.thumbVisibility, isTrue);
      expect(horizontalBar.thumbVisibility, isTrue);
      expect(verticalBar.interactive, isTrue);
      expect(horizontalBar.interactive, isTrue);

      expect(
        verticalBar.notificationPredicate!(
          ScrollUpdateNotification(
            metrics: FixedScrollMetrics(
              minScrollExtent: 0,
              maxScrollExtent: 500,
              pixels: 0,
              viewportDimension: 300,
              axisDirection: AxisDirection.down,
              devicePixelRatio: 1.0,
            ),
            context: tester.element(find.byType(JsonViewer)),
          ),
        ),
        isTrue,
      );

      expect(
        verticalBar.notificationPredicate!(
          ScrollUpdateNotification(
            metrics: FixedScrollMetrics(
              minScrollExtent: 0,
              maxScrollExtent: 500,
              pixels: 0,
              viewportDimension: 300,
              axisDirection: AxisDirection.right,
              devicePixelRatio: 1.0,
            ),
            context: tester.element(find.byType(JsonViewer)),
          ),
        ),
        isFalse,
      );

      expect(
        horizontalBar.notificationPredicate!(
          ScrollUpdateNotification(
            metrics: FixedScrollMetrics(
              minScrollExtent: 0,
              maxScrollExtent: 500,
              pixels: 0,
              viewportDimension: 300,
              axisDirection: AxisDirection.right,
              devicePixelRatio: 1.0,
            ),
            context: tester.element(find.byType(JsonViewer)),
          ),
        ),
        isTrue,
      );
    });

    testWidgets('Scrollbars respond to mouse drag navigation', (tester) async {
      tester.view.physicalSize = const Size(300, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final widePayload = <String, dynamic>{
        for (int i = 0; i < 18; i++)
          'long_field_name_$i':
              'very long value content that exceeds the screen width ${"x" * 150}',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: JsonViewer(
                data: widePayload,
                thumbVisibility: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final jvState = tester.state(find.byType(JsonViewer)) as dynamic;
      final vCtrl = jvState.contentScrollControllerForTest as ScrollController;
      final hCtrl =
          jvState.horizontalScrollControllerForTest as ScrollController;

      expect(vCtrl.position.maxScrollExtent, greaterThan(0));
      expect(hCtrl.position.maxScrollExtent, greaterThan(0));

      await tester.dragFrom(
        const Offset(296, 45),
        const Offset(0, 80),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(vCtrl.offset, greaterThan(0));

      await tester.dragFrom(
        const Offset(60, 296),
        const Offset(80, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(hCtrl.offset, greaterThan(0));
    });

    testWidgets(
        'Scrollbar painter padding is zero even when ancestor has safe area padding',
        (tester) async {
      final sampleData = <String, dynamic>{
        for (int i = 0; i < 20; i++)
          'long_key_$i': 'long_value_$i ${"x" * 100}',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(bottom: 34.0, top: 44.0),
            ),
            child: Scaffold(
              body: SizedBox(
                width: 300,
                height: 300,
                child: JsonViewer(
                  data: sampleData,
                  thumbVisibility: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollbars = find.byType(Scrollbar);
      expect(scrollbars, findsNWidgets(2));

      int verifiedPainters = 0;
      for (int i = 0; i < scrollbars.evaluate().length; i++) {
        final elem = scrollbars.at(i);
        elem.evaluate().first.visitChildren((child) {
          if (child is StatefulElement) {
            final state = child.state;
            try {
              final painter = (state as dynamic).scrollbarPainter;
              expect(painter.padding, equals(EdgeInsets.zero));
              verifiedPainters++;
            } catch (_) {}
          }
        });
      }
      expect(verifiedPainters, equals(2));
    });
  });
}
