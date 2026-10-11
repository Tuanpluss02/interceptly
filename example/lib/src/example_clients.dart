import 'package:chopper/chopper.dart' as chopper;
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:interceptly/interceptly.dart';

class ExampleClients {
  ExampleClients({
    required this.baseUrl,
    required this.dio,
    required this.httpClient,
    required this.chopperClient,
  });

  factory ExampleClients.create({required String baseUrl}) {
    Interceptly.instance.clearNetworkSimulation();

    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    )..interceptors.add(InterceptlyDioInterceptor());

    final httpClient = InterceptlyHttpClient.wrap(http.Client());

    final chopperClient = chopper.ChopperClient(
      baseUrl: Uri.parse(baseUrl),
      interceptors: <chopper.Interceptor>[InterceptlyChopperInterceptor()],
    );

    return ExampleClients(
      baseUrl: baseUrl,
      dio: dio,
      httpClient: httpClient,
      chopperClient: chopperClient,
    );
  }

  final String baseUrl;
  final Dio dio;
  final http.Client httpClient;
  final chopper.ChopperClient chopperClient;
}
