import 'dart:convert';
import 'dart:io';

import 'package:interceptly_mcp/interceptly_mcp.dart';
import 'package:test/test.dart';

void main() {
  const binPath = 'bin/interceptly_mcp.dart';

  group('CLI Executable', () {
    test('--help displays usage and exits with 0', () async {
      final result = await Process.run('dart', [binPath, '--help']);

      expect(result.exitCode, 0);
      final output = '${result.stdout}\n${result.stderr}';
      expect(output, contains('Usage: interceptly_mcp'));
      expect(output, contains('--uri'));
      expect(output, contains('--allow-mutation'));
      expect(output, contains('--dtd-uri'));
    });

    test('--version displays version and exits with 0', () async {
      final result = await Process.run('dart', [binPath, '--version']);

      expect(result.exitCode, 0);
      final output = '${result.stdout}\n${result.stderr}';
      expect(output, contains(packageVersion));
    });

    test('rejects non-loopback --uri with non-zero exit code', () async {
      final result = await Process.run('dart', [
        binPath,
        '--uri',
        'ws://remote.evil.com:9999/ws',
      ]);

      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('Security error'));
    });

    test(
      'zone specification routes print to stderr instead of stdout',
      () async {
        final process = await Process.start('dart', [binPath]);

        final stderrLines = <String>[];
        final stdoutLines = <String>[];

        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(stdoutLines.add);
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(stderrLines.add);

        final initRequest = jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {
            'protocolVersion': '2024-11-05',
            'capabilities': {},
            'clientInfo': {'name': 'test_cli', 'version': '1.0.0'},
          },
        });

        process.stdin.writeln(initRequest);

        await Future<void>.delayed(const Duration(milliseconds: 300));
        process.kill();
        await process.exitCode;

        for (final line in stdoutLines) {
          expect(
            () => jsonDecode(line),
            returnsNormally,
            reason: 'Stdout line must be valid JSON: "$line"',
          );
        }
      },
    );
  });
}
