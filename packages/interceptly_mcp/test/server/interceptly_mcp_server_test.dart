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

void main() {
  late FakeVmServiceClient fakeClient;
  late StreamController<String> clientToServer;
  late StreamController<String> serverToClient;
  late StreamChannel<String> clientChannel;
  late StreamChannel<String> serverChannel;
  late ServerConnection serverConnection;

  Future<void> setupServer({bool allowMutation = false}) async {
    fakeClient = FakeVmServiceClient();
    clientToServer = StreamController<String>();
    serverToClient = StreamController<String>();

    clientChannel = StreamChannel<String>.withCloseGuarantee(
      serverToClient.stream,
      clientToServer.sink,
    );
    serverChannel = StreamChannel<String>.withCloseGuarantee(
      clientToServer.stream,
      serverToClient.sink,
    );

    InterceptlyMcpServer(
      serverChannel,
      vmServiceClient: fakeClient,
      allowMutation: allowMutation,
    );

    final client = MCPClient(
      Implementation(name: 'test_client', version: '1.0.0'),
    );
    serverConnection = client.connectServer(clientChannel);
    await serverConnection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: ClientCapabilities(),
        clientInfo: Implementation(name: 'test_client', version: '1.0.0'),
      ),
    );
  }

  tearDown(() async {
    await clientToServer.close();
    await serverToClient.close();
  });

  group('InterceptlyMcpServer Tools', () {
    test('lists all expected tools', () async {
      await setupServer();
      final listResult = await serverConnection.listTools();
      final toolNames = listResult.tools.map((t) => t.name).toSet();

      expect(
        toolNames,
        containsAll([
          'ping',
          'list_requests',
          'get_request_detail',
          'set_network_simulation',
          'clear_traffic',
          'export_curl',
          'connect_app',
        ]),
      );
    });

    test('ping invokes ext.interceptly.ping and formats status', () async {
      await setupServer();
      fakeClient.onInvoke = (method, [params]) {
        return {
          'status': 'ok',
          'appName': 'TestFlutterApp',
          'extensionApiVersion': 1,
          'requestCount': 42,
        };
      };

      final result = await serverConnection.callTool(
        CallToolRequest(name: 'ping'),
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('Interceptly Status: CONNECTED'));
      expect(text, contains('TestFlutterApp'));
      expect(text, contains('Total Recorded Requests: 42'));
    });

    test('list_requests sends since_id and filters to extension', () async {
      await setupServer();
      fakeClient.onInvoke = (method, [params]) {
        return {
          'count': 1,
          'requests': [
            {
              'id': 105,
              'method': 'GET',
              'url': 'https://api.example.com/items',
              'statusCode': 200,
            },
          ],
        };
      };

      final result = await serverConnection.callTool(
        CallToolRequest(
          name: 'list_requests',
          arguments: {
            'since_id': '100',
            'status_filter': 'failed',
            'search': 'users',
            'limit': 10,
          },
        ),
      );

      expect(result.isError, isNot(true));
      expect(
        fakeClient.invokedMethods,
        contains('ext.interceptly.list_requests'),
      );
      final lastArgs = fakeClient.invokedArgs.last!;
      expect(lastArgs['since_id'], '100');
      expect(lastArgs['status_filter'], 'failed');
      expect(lastArgs['search'], 'users');
      expect(lastArgs['limit'], '10');
    });

    test('get_request_detail passes id, part, offset, and max_chars', () async {
      await setupServer();
      fakeClient.onInvoke = (method, [params]) {
        return {
          'id': '10',
          'part': 'response_body',
          'responseBody': '{"hello":"world"}',
        };
      };

      final result = await serverConnection.callTool(
        CallToolRequest(
          name: 'get_request_detail',
          arguments: {
            'id': '10',
            'part': 'response_body',
            'offset': 100,
            'max_chars': 500,
          },
        ),
      );

      expect(result.isError, isNot(true));
      final lastArgs = fakeClient.invokedArgs.last!;
      expect(lastArgs['id'], '10');
      expect(lastArgs['part'], 'response_body');
      expect(lastArgs['offset'], '100');
      expect(lastArgs['max_chars'], '500');
    });

    test(
      'set_network_simulation is blocked when allowMutation is false',
      () async {
        await setupServer(allowMutation: false);

        final result = await serverConnection.callTool(
          CallToolRequest(
            name: 'set_network_simulation',
            arguments: {'enabled': true, 'latency_ms': 500},
          ),
        );

        expect(result.isError, isTrue);
        final text = (result.content.first as TextContent).text;
        expect(text, contains('--allow-mutation'));
        expect(
          fakeClient.invokedMethods,
          isNot(contains('ext.interceptly.set_network_simulation')),
        );
      },
    );

    test('clear_traffic is blocked when allowMutation is false', () async {
      await setupServer(allowMutation: false);

      final result = await serverConnection.callTool(
        CallToolRequest(name: 'clear_traffic'),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('--allow-mutation'));
    });

    test('mutation tools succeed when allowMutation is true', () async {
      await setupServer(allowMutation: true);

      final resultSim = await serverConnection.callTool(
        CallToolRequest(
          name: 'set_network_simulation',
          arguments: {'enabled': true, 'latency_ms': 300},
        ),
      );
      expect(resultSim.isError, isNot(true));
      expect(
        fakeClient.invokedMethods,
        contains('ext.interceptly.set_network_simulation'),
      );

      final resultClear = await serverConnection.callTool(
        CallToolRequest(name: 'clear_traffic'),
      );
      expect(resultClear.isError, isNot(true));
      expect(
        fakeClient.invokedMethods,
        contains('ext.interceptly.clear_traffic'),
      );
    });

    test(
      'connect_app validates loopback and rejects remote addresses',
      () async {
        await setupServer();

        final rejectResult = await serverConnection.callTool(
          CallToolRequest(
            name: 'connect_app',
            arguments: {'uri': 'ws://evil.com:8181/ws'},
          ),
        );
        expect(rejectResult.isError, isTrue);
        expect(
          (rejectResult.content.first as TextContent).text,
          contains('Security error'),
        );

        final acceptResult = await serverConnection.callTool(
          CallToolRequest(
            name: 'connect_app',
            arguments: {'uri': 'ws://127.0.0.1:9999/ws'},
          ),
        );
        expect(acceptResult.isError, isNot(true));
        expect(fakeClient.connectedUri, Uri.parse('ws://127.0.0.1:9999/ws'));
      },
    );
  });
}
