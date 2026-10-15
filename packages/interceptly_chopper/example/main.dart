// ignore_for_file: avoid_print
import 'package:chopper/chopper.dart';
import 'package:interceptly_chopper/interceptly_chopper.dart';

Future<void> main() async {
  final chopper = ChopperClient(
    baseUrl: Uri.parse('https://jsonplaceholder.typicode.com'),
    interceptors: [InterceptlyChopperInterceptor()],
  );

  final response = await chopper.get(Uri.parse('/posts/1'));
  print('Status: ${response.statusCode}');
  chopper.dispose();
}
