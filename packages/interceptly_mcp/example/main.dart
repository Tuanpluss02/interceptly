// ignore_for_file: avoid_print
import 'package:interceptly_mcp/interceptly_mcp.dart';

Future<void> main() async {
  print('Interceptly MCP Server & Client Example');
  print('Package version: $packageVersion');
  print(
    'Compatible extension API versions: '
    '$minCompatibleExtensionApiVersion - $maxCompatibleExtensionApiVersion',
  );

  // Example: Initializing DefaultVmServiceClient for a local Flutter app
  final client = DefaultVmServiceClient(
    explicitUri: Uri.parse('ws://127.0.0.1:54321/ws'),
  );

  print('Configured client for URI: ${client.explicitUri}');

  // In production or CLI, you would connect to the running app:
  // await client.connect(Uri.parse('ws://127.0.0.1:54321/ws'));
  // print('Connected to isolate: ${client.activeIsolateId}');

  await client.disconnect();
}
