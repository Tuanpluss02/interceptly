// ignore_for_file: avoid_print
import 'package:http/http.dart' as http;
import 'package:interceptly_http/interceptly_http.dart';

Future<void> main() async {
  final client = InterceptlyHttpClient(http.Client());

  final response = await client.get(
    Uri.parse('https://jsonplaceholder.typicode.com/posts/1'),
  );
  print('Status: ${response.statusCode}');
  client.close();
}
