import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/adapter.dart';
import 'package:interceptly/interceptly.dart';

void main() {
  group('Interceptly Core Smoke Test', () {
    setUp(() async {
      await Interceptly.resetForTesting();
    });

    tearDown(() async {
      await Interceptly.resetForTesting();
    });

    test('verifies Interceptly facade and engine singletons exist', () async {
      expect(Interceptly.instance, isNotNull);
      expect(Interceptly.engine, isNotNull);
      expect(HttpTrafficCollector.instance, isNotNull);
      expect(RealtimeTrafficCollector.instance, isNotNull);
      expect(HttpCaptureScope, isNotNull);
      expect(RealtimeSessionScope, isNotNull);

      await Interceptly.resetForTesting();
      expect(Interceptly.instance, isNotNull);
    });
  });
}
