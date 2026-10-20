import 'package:chopper/chopper.dart' as chopper;
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_chopper/interceptly_chopper.dart';
import 'package:interceptly_dio/interceptly_dio.dart';
import 'package:interceptly_http/interceptly_http.dart';
import 'package:interceptly_socket_io/interceptly_socket_io.dart';
import 'package:interceptly_web_socket/interceptly_web_socket.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

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

    final httpClient = InterceptlyHttpClient(http.Client());

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

  /// Connects to a WebSocket endpoint relative to [baseUrl], wrapping the
  /// channel with [InterceptlyWebSocketChannel] for realtime inspection.
  InterceptlyWebSocketChannel connectWebSocket(String path) {
    final wsUri = Uri.parse(baseUrl.replaceFirst('http', 'ws')).resolve(path);
    return InterceptlyWebSocketChannel.connect(wsUri);
  }

  /// Connects to a Socket.IO endpoint on [baseUrl], tracking with [InterceptlySocketIo].
  io.Socket createSocketIoClient({String path = '/socket.io'}) {
    final socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setPath(path)
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );
    socket.attachInterceptly();
    return socket;
  }
}
