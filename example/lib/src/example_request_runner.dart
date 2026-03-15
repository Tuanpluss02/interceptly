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
        'https://69b6e039583f543fbd9ec00d.mockapi.io/interceptly/api/user',
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'en-US,en;q=0.9',
            'Connection': 'keep-alive',
          },
        ),
      );
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 0,
        preview: response.data.toString(),
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode ?? 0;
      final preview = e.response?.data?.toString() ?? e.message ?? e.type.name;
      return ExampleRequestResult(statusCode: statusCode, preview: preview);
    }
  }

  Future<ExampleRequestResult> runHttpGet() async {
    final response = await httpClient.get(
      Uri.parse(
          'https://69b6e039583f543fbd9ec00d.mockapi.io/interceptly/api/user'),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Connection': 'keep-alive',
      },
    );
    return ExampleRequestResult(
      statusCode: response.statusCode,
      preview: response.body,
    );
  }

  Future<ExampleRequestResult> runChopperGet() async {
    final response = await chopperClient.get<dynamic, dynamic>(
      Uri.parse(
          'https://69b6e039583f543fbd9ec00d.mockapi.io/interceptly/api/user'),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Connection': 'keep-alive',
      },
    );
    return ExampleRequestResult(
      statusCode: response.statusCode,
      preview: response.body.toString(),
    );
  }

  Future<ExampleRequestResult> runDioError() async {
    try {
      final response = await dio.get<dynamic>('https://httpbin.org/status/503');
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 0,
        preview: 'Unexpected success',
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode ?? 0;
      final preview = e.response?.data?.toString() ?? e.message ?? e.type.name;
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
