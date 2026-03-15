import 'package:chopper/chopper.dart' as chopper;
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

class ExampleRequestRunner {
  const ExampleRequestRunner({
    required this.dio,
    required this.httpClient,
    required this.chopperClient,
  });

  final Dio dio;
  final http.Client httpClient;
  final chopper.ChopperClient chopperClient;

  Future<ExampleRequestResult> runDioGet() async {
    final response = await dio.get<dynamic>(
      'https://jsonplaceholder.typicode.com/posts/1',
    );
    return ExampleRequestResult(
      statusCode: response.statusCode ?? 0,
      preview: response.data.toString(),
    );
  }

  Future<ExampleRequestResult> runHttpGet() async {
    final response = await httpClient.get(
      Uri.parse('https://jsonplaceholder.typicode.com/posts/2'),
    );
    return ExampleRequestResult(
      statusCode: response.statusCode,
      preview: response.body,
    );
  }

  Future<ExampleRequestResult> runChopperGet() async {
    final response = await chopperClient.get<dynamic, dynamic>(
      Uri.parse('/posts/3'),
    );
    return ExampleRequestResult(
      statusCode: response.statusCode,
      preview: response.body.toString(),
    );
  }

  Future<ExampleRequestResult> runDioError() async {
    final response = await dio.get<dynamic>('https://httpbin.org/status/503');
    return ExampleRequestResult(
      statusCode: response.statusCode ?? 0,
      preview: 'Unexpected success',
    );
  }

  void dispose() {
    httpClient.close();
    chopperClient.dispose();
  }
}

class ExampleRequestResult {
  const ExampleRequestResult({required this.statusCode, required this.preview});

  final int statusCode;
  final String preview;
}
