/// Model Context Protocol (MCP) server for Interceptly Flutter network inspector.
library;

export 'src/client/app_discovery.dart';
export 'src/client/vm_service_client.dart';
export 'src/logging.dart' show logStderr;
export 'src/server/interceptly_mcp_server.dart';
export 'src/version.dart'
    show
        interceptlyMcpVersion,
        maxCompatibleExtensionApiVersion,
        minCompatibleExtensionApiVersion,
        packageVersion;
