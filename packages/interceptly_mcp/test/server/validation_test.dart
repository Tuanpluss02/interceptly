/// MCP server validation for numeric coercion.

library;

import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:interceptly_mcp/src/client/vm_service_client.dart';
import 'package:interceptly_mcp/src/server/interceptly_mcp_server.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

class FakeVmServiceClient implements VmServiceClient {
  bool isConnectedValue = true;
  Uri? connectedUriValue = Uri.parse('ws://127.0.0.1:12345/ws');
  String? activeIsolateIdValue = 'isolates/1';
  int? remoteExtensionApiVersionValue = 1;

  final List<String> invokedMethods = [];
  final List<Map<String, String>?> invokedArgs = [];
  Map<String, dynamic> Function(String method, [Map<String, String>? params])?
  onInvoke;

  @override
  bool get isConnected => isConnectedValue;

  @override
  Uri? get connectedUri => connectedUriValue;

  @override
  String? get activeIsolateId => activeIsolateIdValue;

  @override
  int? get remoteExtensionApiVersion => remoteExtensionApiVersionValue;

  @override
  Future<void> connect(Uri wsUri) async {
    connectedUriValue = wsUri;
    isConnectedValue = true;
  }

  @override
  Future<void> disconnect() async {
    isConnectedValue = false;
  }

  @override
  Future<void> ensureConnected() async {}

  @override
  Future<Map<String, dynamic>> invoke(
    String method, [
    Map<String, String>? params,
  ]) async {
    invokedMethods.add(method);
    invokedArgs.add(params);
    if (onInvoke != null) {
      return onInvoke!(method, params);
    }
    return <String, dynamic>{'success': true};
  }
}

/// Builds a connected MCP server pair for validation tests.
Future<(ServerConnection, FakeVmServiceClient)> setupValidationServer() async {
  final fakeClient = FakeVmServiceClient();
  final clientToServer = StreamController<String>();
  final serverToClient = StreamController<String>();
  final clientChannel = StreamChannel<String>.withCloseGuarantee(
    serverToClient.stream,
    clientToServer.sink,
  );
  final serverChannel = StreamChannel<String>.withCloseGuarantee(
    clientToServer.stream,
    serverToClient.sink,
  );
  InterceptlyMcpServer(serverChannel, vmServiceClient: fakeClient);
  final client = MCPClient(
    Implementation(name: 'test_client', version: '1.0.0'),
  );
  final connection = client.connectServer(clientChannel);
  await connection.initialize(
    InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: ClientCapabilities(),
      clientInfo: Implementation(name: 'test_client', version: '1.0.0'),
    ),
  );
  return (connection, fakeClient);
}

void main() {
  group('MCP validation', () {
    test('mcp coerces string numerics for limit', () async {
      final (connection, fakeClient) = await setupValidationServer();
      fakeClient.onInvoke = (method, [params]) => {'count': 0};
      final result = await connection.callTool(
        CallToolRequest(name: 'list_requests', arguments: {'limit': '50'}),
      );
      expect(result.isError, isNot(true));
      expect(fakeClient.invokedArgs.last!['limit'], '50');
    });

    test('mcp coerces string numerics for max_chars and offset', () async {
      final (connection, fakeClient) = await setupValidationServer();
      fakeClient.onInvoke = (method, [params]) => {'id': '1'};
      final result = await connection.callTool(
        CallToolRequest(
          name: 'get_request_detail',
          arguments: {'id': '1', 'max_chars': '500', 'offset': '10'},
        ),
      );
      expect(result.isError, isNot(true));
      expect(fakeClient.invokedArgs.last!['max_chars'], '500');
      expect(fakeClient.invokedArgs.last!['offset'], '10');
    });

    test('mcp rejects out of range limit', () async {
      final (connection, _) = await setupValidationServer();
      final result = await connection.callTool(
        CallToolRequest(name: 'list_requests', arguments: {'limit': '5000'}),
      );
      expect(result.isError, isTrue);
    });

    test(
      'connect_app gracefully handles non-string uri without throwing',
      () async {
        final (connection, _) = await setupValidationServer();
        final result = await connection.callTool(
          CallToolRequest(name: 'connect_app', arguments: {'uri': 12345}),
        );
        expect(result.isError, isTrue);
      },
    );
  });
}
