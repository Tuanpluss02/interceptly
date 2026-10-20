import 'package:interceptly_mcp/src/client/app_discovery.dart';
import 'package:interceptly_mcp/src/client/vm_service_client.dart';
import 'package:test/test.dart';

void main() {
  group('VmServiceClient & AppDiscovery', () {
    test('isLoopbackUri rejects non-loopback hosts', () {
      expect(
        AppDiscovery.isLoopbackUri(Uri.parse('http://192.168.1.100:8080')),
        isFalse,
      );
    });

    test('MultipleAppsException formats candidate list clearly', () {
      final ex = MultipleAppsException([
        DiscoveredApp(
          uri: Uri.parse('ws://127.0.0.1:1111/ws'),
          name: 'App A',
          isolateId: 'isolates/1',
        ),
        DiscoveredApp(
          uri: Uri.parse('ws://127.0.0.1:2222/ws'),
          name: 'App B',
          isolateId: 'isolates/2',
        ),
      ]);

      expect(ex.candidates.length, 2);
      expect(
        ex.toString(),
        contains('Multiple Flutter apps with Interceptly detected'),
      );
      expect(ex.toString(), contains('ws://127.0.0.1:1111/ws'));
      expect(ex.toString(), contains('ws://127.0.0.1:2222/ws'));
    });

    test('VmServiceClient initial state is disconnected', () {
      final client = DefaultVmServiceClient();
      expect(client.isConnected, isFalse);
      expect(client.connectedUri, isNull);
      expect(client.activeIsolateId, isNull);
    });

    test('disconnect resets client connection state', () async {
      final client = DefaultVmServiceClient();
      await client.disconnect();
      expect(client.isConnected, isFalse);
      expect(client.connectedUri, isNull);
      expect(client.activeIsolateId, isNull);
    });
  });
}
