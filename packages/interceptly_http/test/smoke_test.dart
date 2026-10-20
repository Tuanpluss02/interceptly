import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_http/interceptly_http.dart';

void main() {
  setUp(() async {
    await Interceptly.resetForTesting();
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
  });

  group('Interceptly HTTP Smoke Test', () {
    test('instantiates InterceptlyHttpClient with inner http.Client', () {
      final inner = http.Client();
      final client = InterceptlyHttpClient(inner);
      expect(client, isNotNull);
      expect(client.collector, isNotNull);
      client.close();
    });
  });
}
