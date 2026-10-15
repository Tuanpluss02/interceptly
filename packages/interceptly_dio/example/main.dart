// ignore_for_file: avoid_print
import 'package:dio/dio.dart';
import 'package:interceptly_dio/interceptly_dio.dart';

Future<void> main() async {
  final dio = Dio(
    BaseOptions(baseUrl: 'https://jsonplaceholder.typicode.com'),
  )..interceptors.add(InterceptlyDioInterceptor());

  final response = await dio.get('/posts/1');
  print('Status: ${response.statusCode}');
}
