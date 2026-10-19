import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly_dio/interceptly_dio.dart';

void main() {
  group('Interceptly Dio Smoke Test', () {
    test('instantiates InterceptlyDioInterceptor', () {
      final interceptor = InterceptlyDioInterceptor();
      expect(interceptor, isNotNull);
      expect(interceptor.collector, isNotNull);
    });
  });
}
