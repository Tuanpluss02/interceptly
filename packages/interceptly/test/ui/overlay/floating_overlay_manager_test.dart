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

  testWidgets(
      'Double attach or rapid attach/detach/attach does not create duplicate FABs',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();

    FloatingOverlayManager.instance.attach(
      navigatorKey: navKey,
      showFloatingButton: true,
      onFabTap: () {},
    );
    FloatingOverlayManager.instance.detach();
    FloatingOverlayManager.instance.attach(
      navigatorKey: navKey,
      showFloatingButton: true,
      onFabTap: () {},
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('Home')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bug_report), findsOneWidget);
  });

  testWidgets(
      'bringToTop called before overlay entry is mounted does not duplicate FAB',
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

    // Call bringToTop before pump (before entry is mounted!)
    FloatingOverlayManager.instance.bringToTop();

    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);
  });

  testWidgets(
      'Rapid route operations during startup do not duplicate FAB',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();

    FloatingOverlayManager.instance.attach(
      navigatorKey: navKey,
      showFloatingButton: true,
      onFabTap: () {},
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('Page 1')),
      ),
    );

    // Rapidly schedule route observer events and bringToTop before frame settles
    final obs = FloatingOverlayManager.instance.navigatorObserver;
    final r1 = MaterialPageRoute(builder: (_) => const Scaffold(body: Text('R1')));
    final r2 = MaterialPageRoute(builder: (_) => const Scaffold(body: Text('R2')));
    obs.didPush(r1, null);
    obs.didPush(r2, r1);
    obs.didPop(r2, r1);
    obs.didReplace(newRoute: r2, oldRoute: r1);
    FloatingOverlayManager.instance.scheduleBringToTopPostFrame();
    FloatingOverlayManager.instance.bringToTop();

    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);
  });

  testWidgets(
      'Rapid toggle of setHiddenForSession maintains at most one FAB',
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

    // Rapid toggle
    FloatingOverlayManager.instance.setHiddenForSession(true);
    FloatingOverlayManager.instance.setHiddenForSession(false);
    FloatingOverlayManager.instance.setHiddenForSession(true);
    FloatingOverlayManager.instance.setHiddenForSession(false);

    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);

    FloatingOverlayManager.instance.setHiddenForSession(true);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bug_report), findsNothing);

    FloatingOverlayManager.instance.setHiddenForSession(false);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);
  });

  testWidgets(
      'Attach with new navigatorKey cleanly unlinks previous entry without duplicates',
      (tester) async {
    final navKey1 = GlobalKey<NavigatorState>();
    final navKey2 = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey1,
        home: const Scaffold(body: Text('Nav 1')),
      ),
    );

    FloatingOverlayManager.instance.attach(
      navigatorKey: navKey1,
      showFloatingButton: true,
      onFabTap: () {},
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);

    // Attach to new navigator
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey2,
        home: const Scaffold(body: Text('Nav 2')),
      ),
    );

    FloatingOverlayManager.instance.attach(
      navigatorKey: navKey2,
      showFloatingButton: true,
      onFabTap: () {},
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);
  });
}



