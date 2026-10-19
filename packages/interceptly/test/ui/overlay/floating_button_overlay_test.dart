import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/ui/overlay/draggable_fab.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('interceptly_fab_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tempDir.path;
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    Interceptly.detach();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('DraggableFab resilience tests', () {
    testWidgets(
      'DraggableFab stays on screen when rotated between landscape and portrait',
      (tester) async {
        tester.view.physicalSize = const Size(800, 400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: DraggableFab(
                child: SizedBox(
                  key: ValueKey('fab_btn'),
                  width: 44,
                  height: 44,
                  child: Text('FAB'),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        final fabFinder = find.byKey(const ValueKey('fab_btn'));
        var topLeft = tester.getTopLeft(fabFinder);
        expect(topLeft.dx, 800 - 44);

        tester.view.physicalSize = const Size(400, 800);
        await tester.pumpAndSettle();

        topLeft = tester.getTopLeft(fabFinder);
        expect(topLeft.dx, 400 - 44);
        expect(topLeft.dy >= 0 && topLeft.dy <= 800 - 44, isTrue);

        tester.view.physicalSize = const Size(800, 400);
        await tester.pumpAndSettle();

        topLeft = tester.getTopLeft(fabFinder);
        expect(topLeft.dx, 800 - 44);
        expect(topLeft.dy >= 0 && topLeft.dy <= 400 - 44, isTrue);
      },
    );

    testWidgets(
      'DraggableFab recovers gracefully when starting with Size.zero',
      (tester) async {
        tester.view.physicalSize = Size.zero;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: DraggableFab(
                child: SizedBox(
                  key: ValueKey('fab_btn'),
                  width: 44,
                  height: 44,
                  child: Text('FAB'),
                ),
              ),
            ),
          ),
        );

        await tester.pump();

        tester.view.physicalSize = const Size(400, 800);
        await tester.pumpAndSettle();

        final fabFinder = find.byKey(const ValueKey('fab_btn'));
        final topLeft = tester.getTopLeft(fabFinder);
        expect(topLeft.dx, 400 - 44);
        expect(topLeft.dy >= 0 && topLeft.dy <= 800 - 44, isTrue);
      },
    );

    testWidgets('DraggableFab clamps within securityTop and securityBottom', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DraggableFab(
              securityTop: 50,
              securityBottom: 60,
              child: SizedBox(
                key: ValueKey('fab_btn'),
                width: 44,
                height: 44,
                child: Text('FAB'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final fabFinder = find.byKey(const ValueKey('fab_btn'));

      await tester.drag(fabFinder, const Offset(0, -1000));
      await tester.pumpAndSettle();

      var topLeft = tester.getTopLeft(fabFinder);
      expect(topLeft.dy, 50);

      await tester.drag(fabFinder, const Offset(0, 2000));
      await tester.pumpAndSettle();

      topLeft = tester.getTopLeft(fabFinder);
      expect(topLeft.dy, 800 - 44 - 60);
    });

    testWidgets('DraggableFab snaps on pan cancel gesture', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DraggableFab(
              child: SizedBox(
                key: ValueKey('fab_btn'),
                width: 44,
                height: 44,
                child: Text('FAB'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final fabFinder = find.byKey(const ValueKey('fab_btn'));

      final gesture = await tester.startGesture(tester.getCenter(fabFinder));
      await gesture.moveBy(const Offset(-150, 0));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();

      final topLeft = tester.getTopLeft(fabFinder);
      expect(topLeft.dx == 0 || topLeft.dx == 400 - 44, isTrue);
    });
  });

  group('Interceptly Overlay Lifecycle tests', () {
    testWidgets('Interceptly.init inserts and keeps FAB visible above pages', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: Text('Home Page')),
          ),
        ),
      );

      await tester.runAsync(() async {
        await Interceptly.init(
          navigatorKey: navKey,
          showFloatingButton: true,
        );
      });

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bug_report), findsOneWidget);

      navKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => const Scaffold(
            backgroundColor: Colors.red,
            body: Center(child: Text('Detail Page')),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bug_report), findsOneWidget);

      Interceptly.detach();
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bug_report), findsNothing);
    });

    testWidgets('Tapping FAB on a pushed page opens inspector', (tester) async {
      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: Text('Home Page')),
          ),
        ),
      );

      await tester.runAsync(() async {
        await Interceptly.init(
          navigatorKey: navKey,
          showFloatingButton: true,
        );
      });

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bug_report), findsOneWidget);

      navKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.red,
            body: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: const SizedBox.expand(
                  child: Text('Detail Page Covering Screen'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.bug_report));
      await tester.pumpAndSettle();

      expect(find.text('Interceptly'), findsOneWidget);

      Interceptly.detach();
      await tester.pumpAndSettle();
    });

    testWidgets(
      'FAB stays on top and tappable after pushReplacement (splash to home)',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navKey,
            home: const Scaffold(
              backgroundColor: Colors.blue,
              body: Center(child: Text('Splash Screen')),
            ),
          ),
        );

        await tester.runAsync(() async {
          await Interceptly.init(
            navigatorKey: navKey,
            showFloatingButton: true,
          );
        });

        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.bug_report), findsOneWidget);

        navKey.currentState!.pushReplacement(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.green,
              body: Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const SizedBox.expand(
                    child: Text('Home Screen Replacing Splash'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.bug_report), findsOneWidget);

        await tester.tap(find.byIcon(Icons.bug_report));
        await tester.pumpAndSettle();

        expect(find.text('Interceptly'), findsOneWidget);

        Interceptly.detach();
        await tester.pumpAndSettle();
      },
    );

    testWidgets('App restart / re-initialization restores FAB cleanly', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const Scaffold(
            body: Center(child: Text('Initial Run')),
          ),
        ),
      );

      await tester.runAsync(() async {
        await Interceptly.init(
          navigatorKey: navKey,
          showFloatingButton: true,
        );
      });

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bug_report), findsOneWidget);

      final restartedNavKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: restartedNavKey,
          home: const Scaffold(
            body: Center(child: Text('Restarted App')),
          ),
        ),
      );

      await tester.runAsync(() async {
        await Interceptly.init(
          navigatorKey: restartedNavKey,
          showFloatingButton: true,
        );
      });

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bug_report), findsOneWidget);

      Interceptly.detach();
      await tester.pumpAndSettle();
    });

    testWidgets(
      'FAB retains dragged position across route push and pushReplacement',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navKey,
            home: const Scaffold(body: Text('Initial Screen')),
          ),
        );

        await tester.runAsync(() async {
          await Interceptly.init(
            navigatorKey: navKey,
            showFloatingButton: true,
          );
        });
        await tester.pumpAndSettle();

        final fabFinder = find.byIcon(Icons.bug_report);
        expect(fabFinder, findsOneWidget);

        await tester.drag(fabFinder, const Offset(0, -150));
        await tester.pumpAndSettle();

        final draggedTopLeft = tester.getTopLeft(fabFinder);

        navKey.currentState!.push(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('New Page')),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.getTopLeft(find.byIcon(Icons.bug_report)).dy,
          equals(draggedTopLeft.dy),
        );

        navKey.currentState!.pushReplacement(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Replacement Page')),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.getTopLeft(find.byIcon(Icons.bug_report)).dy,
          equals(draggedTopLeft.dy),
        );

        Interceptly.detach();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'AppLifecycleState.resumed ensures FAB is active and on top',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navKey,
            home: const Scaffold(body: Text('Lifecycle Test Screen')),
          ),
        );

        await tester.runAsync(() async {
          await Interceptly.init(
            navigatorKey: navKey,
            showFloatingButton: true,
          );
        });
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.bug_report), findsOneWidget);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.paused,
        );
        await tester.pumpAndSettle();

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.bug_report), findsOneWidget);

        await tester.tap(find.byIcon(Icons.bug_report));
        await tester.pumpAndSettle();

        expect(find.text('Interceptly'), findsOneWidget);

        Interceptly.detach();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Inspector open and pop cycle cleanly manages overlay visibility',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navKey,
            home: const Scaffold(body: Text('Home Screen')),
          ),
        );

        await tester.runAsync(() async {
          await Interceptly.init(
            navigatorKey: navKey,
            showFloatingButton: true,
          );
        });
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.bug_report), findsOneWidget);

        Interceptly.showInspector();
        await tester.pumpAndSettle();

        expect(find.text('Interceptly'), findsOneWidget);

        navKey.currentState!.pop();
        await tester.pumpAndSettle();

        expect(find.text('Interceptly'), findsNothing);
        expect(find.byIcon(Icons.bug_report), findsOneWidget);

        Interceptly.detach();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Rapid successive pushes and pops maintain FAB visibility on top',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navKey,
            home: const Scaffold(body: Text('Base Screen')),
          ),
        );

        await tester.runAsync(() async {
          await Interceptly.init(
            navigatorKey: navKey,
            showFloatingButton: true,
          );
        });
        await tester.pumpAndSettle();

        for (var i = 1; i <= 5; i++) {
          navKey.currentState!.push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                body: Center(child: Text('Screen $i')),
              ),
            ),
          );
        }
        await tester.pumpAndSettle();

        expect(find.text('Screen 5'), findsOneWidget);
        expect(find.byIcon(Icons.bug_report), findsOneWidget);

        navKey.currentState!.pop();
        navKey.currentState!.pop();
        navKey.currentState!.pop();
        await tester.pumpAndSettle();

        expect(find.text('Screen 2'), findsOneWidget);
        expect(find.byIcon(Icons.bug_report), findsOneWidget);

        await tester.tap(find.byIcon(Icons.bug_report));
        await tester.pumpAndSettle();
        expect(find.text('Interceptly'), findsOneWidget);

        Interceptly.detach();
        await tester.pumpAndSettle();
      },
    );
  });
}
