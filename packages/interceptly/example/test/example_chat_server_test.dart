import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:example/src/example_local_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExampleLocalServer /ws/chat tests', () {
    late ExampleLocalServer server;

    setUp(() async {
      server = ExampleLocalServer();
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    test('connects to /ws/chat and receives welcome + agent greeting',
        () async {
      final wsUrl = '${server.baseUrl.replaceFirst('http', 'ws')}/ws/chat';
      final socket = await WebSocket.connect(wsUrl);

      final messages = <Map<String, dynamic>>[];
      final completer = Completer<void>();

      final sub = socket.listen((dynamic raw) {
        final decoded = jsonDecode(raw.toString()) as Map<String, dynamic>;
        messages.add(decoded);
        if (messages.length >= 2 && !completer.isCompleted) {
          completer.complete();
        }
      });

      await completer.future.timeout(const Duration(seconds: 4));

      expect(messages.length, greaterThanOrEqualTo(2));
      expect(messages[0]['type'], 'system');
      expect(messages[0]['message'], contains('StormX'));

      expect(messages[1]['type'], 'agent_message');
      expect(messages[1]['from'], contains('StormX'));

      // Test ping response
      final pongCompleter = Completer<void>();
      sub.onData((dynamic raw) {
        final decoded = jsonDecode(raw.toString()) as Map<String, dynamic>;
        messages.add(decoded);
        if (decoded['message'] != null &&
            decoded['message'].toString().toLowerCase().contains('pong') &&
            !pongCompleter.isCompleted) {
          pongCompleter.complete();
        }
      });

      socket.add(jsonEncode({'type': 'chat', 'message': 'ping'}));
      await pongCompleter.future.timeout(const Duration(seconds: 3));

      await socket.close();
      await sub.cancel();
    });
  });
}
