import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:test/test.dart';

void main() {
  Process? appProcess;
  Process? mcpProcess;

  tearDown(() async {
    mcpProcess?.kill(ProcessSignal.sigterm);
    await mcpProcess?.exitCode;
    appProcess?.kill(ProcessSignal.sigterm);
    await appProcess?.exitCode;
  });

  test(
    'Full End-to-End integration between Target App, MCP CLI, and MCP Client',
    () async {
      // 1. Spawn target Flutter/Dart application with active VM service
      final appCompleter = Completer<Uri>();
      appProcess = await Process.start('dart', [
        '--enable-vm-service=0',
        'test/e2e/fixtures/target_interceptly_app.dart',
      ]);

      final uriRegex = RegExp(
        r'The Dart VM service is listening on (http://[^\s]+)',
      );

      void handleLine(String line) {
        final match = uriRegex.firstMatch(line);
        if (match != null && !appCompleter.isCompleted) {
          final httpUri = Uri.parse(match.group(1)!);
          final wsPath =
              httpUri.path.endsWith('/')
                  ? '${httpUri.path}ws'
                  : '${httpUri.path}/ws';
          final ws = httpUri.replace(scheme: 'ws', path: wsPath);
          appCompleter.complete(ws);
        }
      }

      appProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(handleLine);
      appProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(handleLine);

      final vmServiceUri = await appCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout:
            () =>
                throw TimeoutException(
                  'Timed out waiting for target app VM service URI',
                ),
      );

      expect(vmServiceUri.scheme, 'ws');

      // 2. Spawn interceptly_mcp CLI process connected to target app
      mcpProcess = await Process.start('dart', [
        'bin/interceptly_mcp.dart',
        '--uri',
        vmServiceUri.toString(),
        '--allow-mutation',
      ]);

      final mcpChannel = stdioChannel(
        input: mcpProcess!.stdout,
        output: mcpProcess!.stdin,
      );

      final client = MCPClient(
        Implementation(name: 'e2e_test_runner', version: '1.0.0'),
      );
      final serverConnection = client.connectServer(mcpChannel);

      // 3. Initialize MCP Server
      final initResult = await serverConnection.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'e2e_test_client', version: '1.0.0'),
        ),
      );
      expect(initResult.serverInfo.name, 'interceptly_mcp');

      // 4. Test tool: ping
      final pingResult = await serverConnection.callTool(
        CallToolRequest(name: 'ping'),
      );
      expect(pingResult.isError, isNot(true));
      final pingText = (pingResult.content.first as TextContent).text;
      expect(pingText, contains('Interceptly Status: CONNECTED'));
      expect(pingText, contains('E2ETestApp'));
      expect(pingText, contains('Total Recorded Requests: 2'));

      // 5. Test tool: list_requests with status_filter: failed
      final listResult = await serverConnection.callTool(
        CallToolRequest(
          name: 'list_requests',
          arguments: {'status_filter': 'failed'},
        ),
      );
      expect(listResult.isError, isNot(true));
      final listJson =
          jsonDecode((listResult.content.first as TextContent).text)
              as Map<String, dynamic>;
      expect(listJson['count'], 1);
      expect(listJson['requests'][0]['id'], '2');
      expect(listJson['requests'][0]['statusCode'], 500);

      // 6. Test tool: get_request_detail with max_chars truncation
      final detailResult = await serverConnection.callTool(
        CallToolRequest(
          name: 'get_request_detail',
          arguments: {'id': 2, 'max_chars': 15},
        ),
      );
      expect(detailResult.isError, isNot(true));
      final detailJson =
          jsonDecode((detailResult.content.first as TextContent).text)
              as Map<String, dynamic>;
      expect(detailJson['id'], '2');
      expect(detailJson['isTruncated'], isTrue);
      expect(detailJson['responseBody'].toString().length, 15);

      // 7. Test tool: export_curl
      final curlResult = await serverConnection.callTool(
        CallToolRequest(name: 'export_curl', arguments: {'id': 1}),
      );
      expect(curlResult.isError, isNot(true));
      final curlText = (curlResult.content.first as TextContent).text;
      expect(curlText, contains("curl -X GET 'https://api.example.com/users'"));

      // 8. Test mutation tool: set_network_simulation
      final simResult = await serverConnection.callTool(
        CallToolRequest(
          name: 'set_network_simulation',
          arguments: {'latency_ms': 250},
        ),
      );
      expect(simResult.isError, isNot(true));
      final simJson =
          jsonDecode((simResult.content.first as TextContent).text)
              as Map<String, dynamic>;
      expect(simJson['status'], 'ok');

      // 9. Test mutation tool: clear_traffic
      final clearResult = await serverConnection.callTool(
        CallToolRequest(name: 'clear_traffic'),
      );
      expect(clearResult.isError, isNot(true));

      // Verify traffic is now 0 via ping
      final pingAfterClear = await serverConnection.callTool(
        CallToolRequest(name: 'ping'),
      );
      final pingAfterText = (pingAfterClear.content.first as TextContent).text;
      expect(pingAfterText, contains('Total Recorded Requests: 0'));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
