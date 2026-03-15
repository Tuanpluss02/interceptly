import 'package:chopper/chopper.dart' as chopper;
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:interceptly/interceptly.dart';

class ExampleClients {
  ExampleClients({
    required this.dio,
    required this.httpClient,
    required this.chopperClient,
  });

  factory ExampleClients.create() {
    Interceptly.instance.clearNetworkSimulation();

    final dio = Dio()..interceptors.add(InterceptlyDioInterceptor());
    final httpClient = Interceptly.wrapHttpClient(http.Client());
    final chopperClient = chopper.ChopperClient(
      baseUrl: Uri.parse('https://reqres.in/api'),
      interceptors: <chopper.Interceptor>[InterceptlyChopperInterceptor()],
    );

    return ExampleClients(
      dio: dio,
      httpClient: httpClient,
      chopperClient: chopperClient,
    );
  }

  final Dio dio;
  final http.Client httpClient;
  final chopper.ChopperClient chopperClient;
}
