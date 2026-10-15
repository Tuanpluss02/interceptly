// ignore_for_file: avoid_print
import 'package:interceptly_web_socket/interceptly_web_socket.dart';

Future<void> main() async {
  final channel = InterceptlyWebSocketChannel.connect(
    Uri.parse('wss://echo.websocket.events'),
  );

  channel.stream.listen((message) {
    print('Received: $message');
  });
  channel.sink.add('Hello Interceptly!');

  await Future<void>.delayed(const Duration(seconds: 2));
  await channel.sink.close();
}
