import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_dio/interceptly_dio.dart';

void main() {
  test('InterceptlyDioInterceptor uses shared session by default', () {
    final interceptor = InterceptlyDioInterceptor();
    expect(interceptor.session, same(InspectorSession.instance));
  });
}
