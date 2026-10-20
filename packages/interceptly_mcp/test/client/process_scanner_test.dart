import 'package:interceptly_mcp/src/client/process_scanner.dart';
import 'package:test/test.dart';

void main() {
  group('ProcessScanner', () {
    const scanner = ProcessScanner();

    test('extractDtdUris extracts valid --dtd-uri parameters', () {
      final lines = [
        'dart devtools --machine --dtd-uri ws://127.0.0.1:57055/MVVNIQQQeC4=',
        'flutter run --target lib/main.dart',
        'dart language-server',
      ];

      final uris = scanner.extractDtdUris(lines);
      expect(uris.length, 1);
      expect(uris.first, Uri.parse('ws://127.0.0.1:57055/MVVNIQQQeC4='));
    });

    test('extractDdsUris extracts valid --vm-service-uri parameters', () {
      final lines = [
        'dart development-service --vm-service-uri=http://127.0.0.1:52719/token/ --bind-address=127.0.0.1',
        'some unrelated process',
      ];

      final uris = scanner.extractDdsUris(lines);
      expect(uris.length, 1);
      expect(uris.first, Uri.parse('http://127.0.0.1:52719/token/'));
    });
  });
}
