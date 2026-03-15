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
    try {
      final response = await dio.get<dynamic>(
        'https://reqres.in/api/users?page=1',
      );
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 0,
        preview: response.data.toString(),
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode ?? 0;
      final preview =
          e.response?.data?.toString() ?? e.message ?? e.type.name;
      return ExampleRequestResult(statusCode: statusCode, preview: preview);
    }
  }

  Future<ExampleRequestResult> runHttpGet() async {
    final response = await httpClient.get(
      Uri.parse('https://reqres.in/api/users/2'),
    );
    return ExampleRequestResult(
      statusCode: response.statusCode,
      preview: response.body,
    );
  }

  Future<ExampleRequestResult> runChopperGet() async {
    final response = await chopperClient.get<dynamic, dynamic>(
      Uri.parse('/users/3'),
    );
    return ExampleRequestResult(
      statusCode: response.statusCode,
      preview: response.body.toString(),
    );
  }

  Future<ExampleRequestResult> runDioError() async {
    try {
      final response =
          await dio.get<dynamic>('https://httpbin.org/status/503');
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 0,
        preview: 'Unexpected success',
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode ?? 0;
      final preview =
          e.response?.data?.toString() ?? e.message ?? e.type.name;
      return ExampleRequestResult(statusCode: statusCode, preview: preview);
    }
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
