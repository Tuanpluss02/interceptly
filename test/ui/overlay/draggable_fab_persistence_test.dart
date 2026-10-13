import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/ui/overlay/draggable_fab.dart';

void main() {
  testWidgets('DraggableFab restores position from positionNotifier on remount',
      (tester) async {
    final positionNotifier = ValueNotifier<Offset?>(const Offset(50, 100));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DraggableFab(
            positionNotifier: positionNotifier,
            child: const SizedBox(
              key: ValueKey('fab_content'),
              width: 44,
              height: 44,
              child: Text('FAB'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fabFinder = find.byKey(const ValueKey('fab_content'));
    expect(tester.getTopLeft(fabFinder).dy, 100);

    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DraggableFab(
            positionNotifier: positionNotifier,
            child: const SizedBox(
              key: ValueKey('fab_content'),
              width: 44,
              height: 44,
              child: Text('FAB'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(fabFinder).dy, 100);
  });
}
