// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';

/// Throwing user predicates must fail open and never break the host request.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  InterceptlyEngine throwingEngine() {
    final engine = InterceptlyEngine(
      settings: InterceptlySettings(
        shouldCapture: (_) => throw StateError('boom'),
      ),
    );
    addTearDown(() async {
      try {
        await engine.dispose();
      } catch (_) {}
    });
    return engine;
  }

  group('DefaultHttpTrafficCollector.shouldCapture', () {
    test('throwing predicate returns normally and fails open', () {
      final engine = throwingEngine();
      final collector = DefaultHttpTrafficCollector(engine: engine);
      final uri = Uri.parse('https://a.test/');

      expect(() => collector.shouldCapture(uri), returnsNormally);
      expect(collector.shouldCapture(uri), isTrue);
    });

    test('null uri is captured', () {
      final engine = throwingEngine();
      final collector = DefaultHttpTrafficCollector(engine: engine);
      expect(collector.shouldCapture(null), isTrue);
    });

    test('disabled engine short-circuits to false without evaluating', () {
      final engine = throwingEngine();
      engine.disable();
      final collector = DefaultHttpTrafficCollector(engine: engine);
      expect(
        collector.shouldCapture(Uri.parse('https://a.test/')),
        isFalse,
      );
    });

    test('explicit false predicate still excludes', () {
      final engine = InterceptlyEngine(
        settings: InterceptlySettings(
          shouldCapture: (_) => false,
        ),
      );
      addTearDown(() async {
        try {
          await engine.dispose();
        } catch (_) {}
      });
      final collector = DefaultHttpTrafficCollector(engine: engine);
      expect(
        collector.shouldCapture(Uri.parse('https://a.test/')),
        isFalse,
      );
    });
  });

  group('DefaultRealtimeTrafficCollector.shouldCapture', () {
    test('throwing predicate returns normally and fails open', () {
      final engine = throwingEngine();
      final collector = DefaultRealtimeTrafficCollector(engine: engine);
      final uri = Uri.parse('https://a.test/');

      expect(() => collector.shouldCapture(uri), returnsNormally);
      expect(collector.shouldCapture(uri), isTrue);
    });

    test('openSession with throwing predicate does not throw', () {
      final engine = throwingEngine();
      final collector = DefaultRealtimeTrafficCollector(engine: engine);

      expect(
        () => collector.openSession(uri: Uri.parse('wss://a.test/socket')),
        returnsNormally,
      );
      final scope = collector.openSession(
        uri: Uri.parse('wss://a.test/socket'),
      );
      expect(scope.isClosed, isFalse);
      collector.recordClose(sessionId: scope.sessionId);
    });

    test('recordConnection with throwing predicate does not throw', () {
      final engine = throwingEngine();
      final collector = DefaultRealtimeTrafficCollector(engine: engine);

      expect(
        () => collector.recordConnection(
          sessionId: 'realtime-boom',
          uri: Uri.parse('wss://a.test/socket'),
        ),
        returnsNormally,
      );
    });
  });
}
