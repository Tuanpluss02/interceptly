// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';

/// Release-guard wiring for capture and overlay.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('allowInRelease setting', () {
    test('defaults to false', () {
      expect(const InterceptlySettings().allowInRelease, isFalse);
    });

    test('copyWith preserves and overrides the flag', () {
      const base = InterceptlySettings();
      expect(base.copyWith().allowInRelease, isFalse);
      expect(
        base.copyWith(allowInRelease: true).allowInRelease,
        isTrue,
      );
      expect(
        const InterceptlySettings(allowInRelease: true)
            .copyWith()
            .allowInRelease,
        isTrue,
      );
    });
  });

  group('engine release guard', () {
    test('disallows capture in release unless opted in', () {
      expect(
        InterceptlyEngine.shouldEnableCapture(
          isReleaseMode: true,
          settings: const InterceptlySettings(),
        ),
        isFalse,
      );
      expect(
        InterceptlyEngine.shouldEnableCapture(
          isReleaseMode: true,
          settings: const InterceptlySettings(allowInRelease: true),
        ),
        isTrue,
      );
    });

    test('allows capture in debug/profile regardless of opt-in', () {
      expect(
        InterceptlyEngine.shouldEnableCapture(
          isReleaseMode: false,
          settings: const InterceptlySettings(),
        ),
        isTrue,
      );
      expect(
        InterceptlyEngine.shouldEnableCapture(
          isReleaseMode: false,
          settings: const InterceptlySettings(allowInRelease: true),
        ),
        isTrue,
      );
    });

    test('fresh engine starts enabled in debug test runs', () {
      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);
      expect(engine.isEnabled, isTrue);
    });

    test('configure with opt-in keeps the engine enabled', () {
      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);
      engine.configure(const InterceptlySettings(allowInRelease: true));
      expect(engine.settings.allowInRelease, isTrue);
      expect(engine.isEnabled, isTrue);
    });

    test('configure preserves an explicit pause on the opt-in path', () {
      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);
      engine.disable();
      expect(engine.isEnabled, isFalse);
      engine.configure(const InterceptlySettings(allowInRelease: true));
      expect(engine.isEnabled, isFalse);
    });

    test('configure preserves an explicit pause with default settings', () {
      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);
      engine.disable();
      expect(engine.isEnabled, isFalse);
      engine.configure(const InterceptlySettings());
      expect(engine.isEnabled, isFalse);
    });

    test('initialize does not resume an explicit pause', () async {
      final engine = InterceptlyEngine(
        settings: const InterceptlySettings(persistToDisk: false),
      );
      addTearDown(engine.dispose);
      engine.disable();
      await engine.initialize();
      expect(engine.isEnabled, isFalse);
    });

    test('second dispose returns normally after complete cleanup', () async {
      final engine = InterceptlyEngine(
        settings: const InterceptlySettings(persistToDisk: false),
      );
      engine.recordPending(
        id: 'dispose-rest',
        method: 'GET',
        url: 'https://api.example.com/dispose',
        timestamp: DateTime.now(),
      );
      engine.recordRealtimeConnection(
        id: 'dispose-realtime',
        url: 'wss://api.example.com/socket',
      );
      expect(engine.entries, isNotEmpty);

      await engine.dispose();

      expect(engine.isDisposed, isTrue);
      expect(engine.isEnabled, isFalse);
      expect(engine.entries, isEmpty);
      expect(engine.totalEntries, equals(0));

      await engine.dispose();

      expect(engine.isDisposed, isTrue);
      expect(engine.isEnabled, isFalse);
      expect(engine.entries, isEmpty);
      expect(engine.totalEntries, equals(0));
    });
  });
}
