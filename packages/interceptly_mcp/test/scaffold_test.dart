import 'package:interceptly_mcp/interceptly_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('interceptly_mcp scaffold', () {
    test('exports expected version constants', () {
      expect(packageVersion, '1.0.0');
      expect(minCompatibleExtensionApiVersion, 1);
      expect(maxCompatibleExtensionApiVersion, 1);
    });

    test('logStderr does not throw', () {
      expect(() => logStderr('Test log line'), returnsNormally);
    });
  });
}
