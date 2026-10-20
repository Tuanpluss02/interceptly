import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_dio/interceptly_dio.dart';

void main() {
  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('Interceptly Dio Smoke Test', () {
    test('instantiates InterceptlyDioInterceptor', () {
      final interceptor = InterceptlyDioInterceptor();
      expect(interceptor, isNotNull);
      expect(interceptor.collector, isNotNull);
    });
  });
}
