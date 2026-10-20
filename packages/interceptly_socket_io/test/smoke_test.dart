import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly_socket_io/interceptly_socket_io.dart';

void main() {
  group('Interceptly Socket.IO Smoke Test', () {
    test('loads package and exports valid version', () {
      expect(packageVersion, isNotEmpty);
      expect(packageVersion, equals('1.0.0'));
    });
  });
}
