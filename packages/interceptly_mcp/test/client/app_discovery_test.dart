import 'package:interceptly_mcp/src/client/app_discovery.dart';
import 'package:test/test.dart';

void main() {
  group('AppDiscovery', () {
    test('isLoopbackUri validates 127.0.0.1, localhost, and IPv6 loopback', () {
      expect(
        AppDiscovery.isLoopbackUri(Uri.parse('ws://127.0.0.1:12345/ws')),
        isTrue,
      );
      expect(
        AppDiscovery.isLoopbackUri(Uri.parse('http://localhost:8080/path')),
        isTrue,
      );
      expect(
        AppDiscovery.isLoopbackUri(Uri.parse('ws://[::1]:9000/ws')),
        isTrue,
      );

      expect(
        AppDiscovery.isLoopbackUri(Uri.parse('ws://192.168.1.50:12345/ws')),
        isFalse,
      );
      expect(
        AppDiscovery.isLoopbackUri(Uri.parse('http://evil.com/ws')),
        isFalse,
      );
    });

    test(
      'resolveUri prioritizes explicit URI and normalizes to WebSocket /ws',
      () async {
        final uri = await AppDiscovery.resolveUri(
          explicitUri: Uri.parse('http://localhost:5000/auth_token/'),
          environment: {'INTERCEPTLY_VM_SERVICE_URI': 'ws://127.0.0.1:6000/ws'},
        );

        expect(uri, Uri.parse('ws://localhost:5000/auth_token/ws'));
      },
    );

    test('resolveUri rejects non-loopback explicit URI', () async {
      expect(
        () => AppDiscovery.resolveUri(
          explicitUri: Uri.parse('ws://remote-server.com:12345/ws'),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'resolveUri falls back to INTERCEPTLY_VM_SERVICE_URI when explicit URI is null',
      () async {
        final uri = await AppDiscovery.resolveUri(
          explicitUri: null,
          environment: {
            'INTERCEPTLY_VM_SERVICE_URI': 'http://127.0.0.1:7777/xyz',
          },
        );

        expect(uri, Uri.parse('ws://127.0.0.1:7777/xyz/ws'));
      },
    );

    test(
      'resolveUri returns null when no candidate is configured and DTD unavailable',
      () async {
        final uri = await AppDiscovery.resolveUri(
          explicitUri: null,
          environment: {},
        );

        expect(uri, isNull);
      },
    );
  });
}
