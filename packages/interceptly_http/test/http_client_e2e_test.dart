import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interceptly/interceptly.dart';
import '../lib/src/interceptly_http_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'Scenario 1: End-to-end HTTP client request capture into InspectorSession',
      () async {
    final session = InspectorSession();
    await session.initialize();

    final mockClient = MockClient((request) async {
      if (request.url.path.contains('/api/items')) {
        return http.Response(
          '{"items":[{"id":101,"name":"Widget"}]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('Not Found', 404);
    });

    final client = InterceptlyHttpClient(mockClient, session);
    final response = await client.get(
      Uri.parse('https://api.example.com/api/items'),
      headers: {'Authorization': 'Bearer secret_user_token'},
    );

    expect(response.statusCode, equals(200));

    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (
        session.entries.isEmpty || session.entries.first.statusCode != 200) {
      if (DateTime.now().isAfter(deadline)) {
        fail(
            'Timed out waiting for intercepted entry to settle in InspectorSession');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    final captured = session.entries.first;
    expect(captured.statusCode, equals(200));
    expect(captured.method, equals('GET'));
    expect(captured.url, contains('/api/items'));
    expect(captured.requestHeaders['Authorization'],
        equals('Bearer secret_user_token'));

    session.dispose();
  });
}
