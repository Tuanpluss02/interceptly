import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import '../lib/src/interceptly_dio_interceptor.dart';

void main() {
  test('InterceptlyDioInterceptor uses shared session by default', () {
    final interceptor = InterceptlyDioInterceptor();
    expect(interceptor.session, same(InspectorSession.instance));
  });
}
