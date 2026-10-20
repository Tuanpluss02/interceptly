// ignore_for_file: avoid_print
import 'package:interceptly_socket_io/interceptly_socket_io.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

Future<void> main() async {
  final socket = io.io(
    'https://echo.websocket.events',
    io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .build(),
  );

  final tracker = socket.attachInterceptly();

  socket.on('chat_message', (data) {
    print('Received chat_message: $data');
  });

  socket.connect();
  socket.emit('chat_message', {'text': 'Hello Interceptly Socket.IO!'});

  await Future<void>.delayed(const Duration(seconds: 2));

  tracker.detach();
  socket.disconnect();
}
