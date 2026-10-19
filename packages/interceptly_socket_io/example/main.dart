// ignore_for_file: avoid_print
import 'package:interceptly_socket_io/interceptly_socket_io.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

Future<void> main() async {
  // 1. Create a Socket.IO client instance
  final socket = io.io(
    'https://echo.websocket.events',
    io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .build(),
  );

  // 2. Attach Interceptly inspector (or use InterceptlySocketIo.attach(socket))
  final tracker = socket.attachInterceptly();

  // 3. Listen to incoming events
  socket.on('chat_message', (data) {
    print('Received chat_message: $data');
  });

  // 4. Connect and emit events
  socket.connect();
  socket.emit('chat_message', {'text': 'Hello Interceptly Socket.IO!'});

  await Future<void>.delayed(const Duration(seconds: 2));

  // 5. Clean detach and close
  tracker.detach();
  socket.disconnect();
}
