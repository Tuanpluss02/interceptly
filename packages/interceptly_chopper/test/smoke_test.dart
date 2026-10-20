import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_chopper/interceptly_chopper.dart';

void main() {
  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('Interceptly Chopper Smoke Test', () {
    test('instantiates InterceptlyChopperInterceptor', () {
      final interceptor = InterceptlyChopperInterceptor();
      expect(interceptor, isNotNull);
      expect(interceptor.collector, isNotNull);
    });
  });
}
