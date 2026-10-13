import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/ui/overlay/floating_overlay_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    FloatingOverlayManager.instance.detach();
  });

  testWidgets('FloatingOverlayManager attaches overlay entry without timers',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('Home')),
      ),
    );

    FloatingOverlayManager.instance.attach(
      navigatorKey: navKey,
      showFloatingButton: true,
      onFabTap: () {},
    );

    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bug_report), findsOneWidget);
    expect(FloatingOverlayManager.instance.isAttached, isTrue);
  });

  testWidgets(
      'FloatingOverlayManager brings FAB to top on route push and replacement',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('Page 1')),
      ),
    );

    var tapped = false;
    FloatingOverlayManager.instance.attach(
      navigatorKey: navKey,
      showFloatingButton: true,
      onFabTap: () => tapped = true,
    );
    await tester.pumpAndSettle();

    navKey.currentState!.push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: const SizedBox.expand(child: Text('Page 2')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bug_report), findsOneWidget);
    await tester.tap(find.byIcon(Icons.bug_report));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('FloatingOverlayManager detach removes overlay and resets state',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('Home')),
      ),
    );

    FloatingOverlayManager.instance.attach(
      navigatorKey: navKey,
      showFloatingButton: true,
      onFabTap: () {},
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bug_report), findsOneWidget);

    FloatingOverlayManager.instance.detach();
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bug_report), findsNothing);
    expect(FloatingOverlayManager.instance.isAttached, isFalse);
  });

  testWidgets(
      'FloatingOverlayManager hides FAB for session and restores on restart',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('Home')),
      ),
    );

    FloatingOverlayManager.instance.attach(
      navigatorKey: navKey,
      showFloatingButton: true,
      onFabTap: () {},
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bug_report), findsOneWidget);
    expect(FloatingOverlayManager.instance.isHiddenForSession, isFalse);

    FloatingOverlayManager.instance.setHiddenForSession(true);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bug_report), findsNothing);
    expect(FloatingOverlayManager.instance.isHiddenForSession, isTrue);

    navKey.currentState!.push(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Page 2')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bug_report), findsNothing);

    FloatingOverlayManager.instance.attach(
      navigatorKey: navKey,
      showFloatingButton: true,
      onFabTap: () {},
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bug_report), findsOneWidget);
    expect(FloatingOverlayManager.instance.isHiddenForSession, isFalse);
  });
}
