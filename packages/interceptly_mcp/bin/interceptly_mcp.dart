import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:interceptly_mcp/interceptly_mcp.dart';

void main(List<String> args) {
  runZonedGuarded(
    () => _run(args),
    (error, stack) {
      stderr.writeln('[interceptly_mcp] Uncaught error: $error\n$stack');
      exitCode = 1;
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        stderr.writeln(line);
      },
    ),
  );
}

Future<void> _run(List<String> args) async {
  final parser =
      ArgParser()
        ..addOption(
          'uri',
          abbr: 'u',
          help:
              'Explicit Flutter app VM Service WebSocket URI (e.g. ws://127.0.0.1:54321/ws)',
        )
        ..addOption(
          'dtd-uri',
          abbr: 'd',
          help:
              'Explicit Dart Tooling Daemon (DTD) URI for automatic discovery',
        )
        ..addFlag(
          'allow-mutation',
          negatable: false,
          help: 'Allow mutating tools (set_network_simulation, clear_traffic)',
        )
        ..addFlag(
          'help',
          abbr: 'h',
          negatable: false,
          help: 'Show usage information',
        )
        ..addFlag(
          'version',
          abbr: 'v',
          negatable: false,
          help: 'Show version information',
        );

  final ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Argument error: ${e.message}\n');
    stderr.writeln('Usage: interceptly_mcp [options]');
    stderr.writeln(parser.usage);
    exit(1);
  }

  if (parsed['help'] as bool) {
    stderr.writeln('Usage: interceptly_mcp [options]');
    stderr.writeln(parser.usage);
    exit(0);
  }

  if (parsed['version'] as bool) {
    stderr.writeln('interceptly_mcp version $packageVersion');
    exit(0);
  }

  final rawUri = parsed['uri'] as String?;
  Uri? explicitUri;
  if (rawUri != null && rawUri.trim().isNotEmpty) {
    final parsedUri = Uri.tryParse(rawUri.trim());
    if (parsedUri == null || !AppDiscovery.isLoopbackUri(parsedUri)) {
      stderr.writeln(
        'Security error: --uri must be a loopback address (127.0.0.1 or localhost), got: $rawUri',
      );
      exit(2);
    }
    explicitUri = AppDiscovery.normalizeWsUri(parsedUri);
  }

  final rawDtdUri = parsed['dtd-uri'] as String?;
  Uri? dtdUri;
  if (rawDtdUri != null && rawDtdUri.trim().isNotEmpty) {
    dtdUri = Uri.tryParse(rawDtdUri.trim());
  }

  final allowMutation = parsed['allow-mutation'] as bool;

  final vmServiceClient = DefaultVmServiceClient(
    explicitUri: explicitUri,
    environment: Platform.environment,
    dtdUri: dtdUri,
  );

  final channel = stdioChannel(input: stdin, output: stdout);

  InterceptlyMcpServer(
    channel,
    vmServiceClient: vmServiceClient,
    allowMutation: allowMutation,
  );

  logStderr(
    'Interceptly MCP server initialized (allowMutation: $allowMutation)',
  );

  ProcessSignal.sigint.watch().listen((_) async {
    logStderr('Received SIGINT, shutting down...');
    await vmServiceClient.disconnect();
    exit(0);
  });

  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) async {
      logStderr('Received SIGTERM, shutting down...');
      await vmServiceClient.disconnect();
      exit(0);
    });
  }
}
