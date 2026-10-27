import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';

import '../client/app_discovery.dart';
import '../client/vm_service_client.dart';
import '../version.dart';

/// Interceptly MCP server exposing tools for inspecting and controlling HTTP/WebSocket traffic.
base class InterceptlyMcpServer extends MCPServer
    with ToolsSupport, PromptsSupport {
  InterceptlyMcpServer(
    super.channel, {
    required this.vmServiceClient,
    this.allowMutation = false,
  }) : super.fromStreamChannel(
         implementation: Implementation(
           name: 'interceptly_mcp',
           version: interceptlyMcpVersion,
         ),
         instructions:
             'Interceptly network debugging and traffic inspection MCP server. '
             'Use list_requests and get_request_detail to inspect HTTP/WebSocket traffic '
             'recorded from a running Flutter application.',
       ) {
    _registerTools();
    _registerPrompts();
  }

  /// Client connected to the Flutter application VM Service.
  final VmServiceClient vmServiceClient;

  /// Whether mutation tools (`set_network_simulation`, `clear_traffic`) are enabled.
  final bool allowMutation;

  void _registerTools() {
    registerTool(_pingTool, _handlePing);
    registerTool(_listRequestsTool, _handleListRequests);
    registerTool(_getRequestDetailTool, _handleGetRequestDetail);
    registerTool(_listRealtimeFramesTool, _handleListRealtimeFrames);
    registerTool(_getRealtimeFrameDetailTool, _handleGetRealtimeFrameDetail);
    registerTool(_getTrafficSummaryTool, _handleGetTrafficSummary);
    registerTool(_setNetworkSimulationTool, _handleSetNetworkSimulation);
    registerTool(_clearTrafficTool, _handleClearTraffic);
    registerTool(_exportCurlTool, _handleExportCurl);
    registerTool(_connectAppTool, _handleConnectApp);
  }

  void _registerPrompts() {
    addPrompt(
      Prompt(
        name: 'analyze_network_traffic',
        description:
            'Inspects recent network requests recorded by Interceptly and identifies failures or bottlenecks.',
      ),
      (request) => GetPromptResult(
        description:
            'Analyzes recorded network traffic for failures and performance issues.',
        messages: [
          PromptMessage(
            role: Role.user,
            content: TextContent(
              text:
                  'Please inspect recorded network traffic using `list_requests` with `status_filter: "failed"`. '
                  'For any failed requests, fetch their full headers and response bodies with `get_request_detail` '
                  'and analyze the root causes and suggest solutions.',
            ),
          ),
        ],
      ),
    );
  }

  final Tool _pingTool = Tool(
    name: 'ping',
    description:
        'Checks connection to the running Flutter app and Interceptly extension RPCs.',
    inputSchema: Schema.object(),
  );

  final Tool _listRequestsTool = Tool(
    name: 'list_requests',
    description:
        'Lists recorded network requests with optional filtering, deep multi-phase search, and cursor pagination.',
    inputSchema: Schema.object(
      properties: {
        'since_id': Schema.string(
          description:
              'Return only requests with an ID cursor strictly after this value for forward pagination.',
        ),
        'status_filter': EnumSchema.untitledSingleSelect(
          description:
              'Filter by HTTP status category: all, failed, 2xx, 3xx, 4xx, 5xx',
          values: ['all', 'failed', '2xx', '3xx', '4xx', '5xx'],
        ),
        'search': Schema.string(
          description:
              'Search query to filter requests across URL, method, headers (request and response), error messages, and payload bodies.',
        ),
        'search_body': Schema.bool(
          description:
              'Whether to search within request and response bodies (default: true). Set to false for metadata-only search.',
        ),
        'limit': Schema.combined(
          anyOf: [
            Schema.int(
              description:
                  'Maximum number of requests to return (default: 20, max: 100).',
            ),
            Schema.string(
              description:
                  'Maximum number of requests to return as a numeric string.',
            ),
          ],
        ),
      },
    ),
  );

  final Tool _getRequestDetailTool = Tool(
    name: 'get_request_detail',
    description:
        'Retrieves detailed information (headers, body, timings) for a specific request by ID.',
    inputSchema: Schema.object(
      properties: {
        'id': Schema.string(
          description:
              'The unique ID of the request to inspect (e.g. from list_requests).',
        ),
        'part': EnumSchema.untitledSingleSelect(
          description:
              'The specific section of the request to fetch (all, request_body, response_body, request_headers, response_headers). Default: all.',
          values: [
            'all',
            'request_body',
            'response_body',
            'request_headers',
            'response_headers',
          ],
        ),
        'max_chars': Schema.combined(
          anyOf: [
            Schema.int(
              description:
                  'Maximum characters to return for body payloads before truncating. Default: 4000.',
            ),
            Schema.string(
              description: 'Maximum characters as a numeric string.',
            ),
          ],
        ),
        'offset': Schema.combined(
          anyOf: [
            Schema.int(
              description:
                  'Starting character offset for reading large or truncated body content.',
            ),
            Schema.string(description: 'Starting offset as a numeric string.'),
          ],
        ),
      },
      required: ['id'],
    ),
  );

  final Tool _listRealtimeFramesTool = Tool(
    name: 'list_realtime_frames',
    description:
        'Lists recorded WebSocket and Realtime frames with optional filtering by session, direction, type, and cursor pagination.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description:
              'Filter frames by WebSocket / Realtime session ID (e.g. from realtime summary or session list).',
        ),
        'direction': EnumSchema.untitledSingleSelect(
          description:
              'Filter by frame direction: sent (outgoing), received (incoming), or all.',
          values: ['all', 'sent', 'received', 'outgoing', 'incoming'],
        ),
        'type': EnumSchema.untitledSingleSelect(
          description:
              'Filter by frame type: text, binary, ping, pong, close, or all.',
          values: ['all', 'text', 'binary', 'ping', 'pong', 'close'],
        ),
        'since_id': Schema.string(
          description:
              'Return only frames with an ID cursor strictly after this value for forward pagination.',
        ),
        'limit': Schema.combined(
          anyOf: [
            Schema.int(
              description:
                  'Maximum number of frames to return (default: 50, max: 200).',
            ),
            Schema.string(description: 'Maximum frames as a numeric string.'),
          ],
        ),
      },
    ),
  );

  final Tool _getRealtimeFrameDetailTool = Tool(
    name: 'get_realtime_frame_detail',
    description:
        'Retrieves detailed payload content and metadata for a specific WebSocket / Realtime frame.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The unique session ID to which the frame belongs.',
        ),
        'frame_id': Schema.string(
          description: 'The unique ID of the frame to inspect.',
        ),
        'max_chars': Schema.combined(
          anyOf: [
            Schema.int(
              description:
                  'Maximum characters to return for the payload before truncating. Default: 4000.',
            ),
            Schema.string(
              description: 'Maximum characters as a numeric string.',
            ),
          ],
        ),
        'offset': Schema.combined(
          anyOf: [
            Schema.int(
              description:
                  'Starting character offset for reading large or truncated payload content.',
            ),
            Schema.string(description: 'Starting offset as a numeric string.'),
          ],
        ),
      },
      required: ['session_id', 'frame_id'],
    ),
  );

  final Tool _getTrafficSummaryTool = Tool(
    name: 'get_traffic_summary',
    description:
        'Provides a fast, high-level summary of recorded HTTP and Realtime traffic metrics (total requests, failure rate, status code distribution, latency percentiles p50/p90/p95/p99, bandwidth, active realtime sessions, network simulation state).',
    inputSchema: Schema.object(),
  );

  final Tool _setNetworkSimulationTool = Tool(
    name: 'set_network_simulation',
    description:
        'Simulates network latency, throttling, or offline conditions on the connected Flutter app.',
    inputSchema: Schema.object(
      properties: {
        'profile': Schema.string(
          description:
              'Preset profile name: "none", "offline", "slow3g", "fast3g", "4g", "wifi", or "custom".',
        ),
        'enabled': Schema.bool(
          description:
              'Enable or disable network simulation. Setting false resets to "none".',
        ),
        'offline': Schema.bool(
          description: 'If true, simulates complete network failure (offline).',
        ),
        'latency_ms': Schema.combined(
          anyOf: [
            Schema.int(description: 'Simulated network delay in milliseconds.'),
            Schema.string(description: 'Latency as a numeric string.'),
          ],
        ),
        'download_kbps': Schema.combined(
          anyOf: [
            Schema.int(description: 'Simulated download bandwidth in Kbps.'),
            Schema.string(
              description: 'Download bandwidth as a numeric string.',
            ),
          ],
        ),
        'upload_kbps': Schema.combined(
          anyOf: [
            Schema.int(description: 'Simulated upload bandwidth in Kbps.'),
            Schema.string(description: 'Upload bandwidth as a numeric string.'),
          ],
        ),
      },
    ),
  );

  final Tool _clearTrafficTool = Tool(
    name: 'clear_traffic',
    description:
        'Clears all recorded network requests and reset traffic buffers in the connected Flutter app.',
    inputSchema: Schema.object(),
  );

  final Tool _exportCurlTool = Tool(
    name: 'export_curl',
    description:
        'Exports a recorded network request as an executable, replayable cURL command.',
    inputSchema: Schema.object(
      properties: {
        'id': Schema.string(
          description:
              'The unique ID of the request to export as cURL (e.g. from list_requests).',
        ),
      },
      required: ['id'],
    ),
  );

  final Tool _connectAppTool = Tool(
    name: 'connect_app',
    description:
        'Explicitly connects the MCP server to a running Flutter application VM Service WebSocket URI.',
    inputSchema: Schema.object(
      properties: {
        'uri': Schema.string(
          description:
              'Loopback VM Service WebSocket URI (e.g. ws://127.0.0.1:51234/ws).',
        ),
      },
      required: ['uri'],
    ),
  );

  Future<CallToolResult> _handlePing(CallToolRequest request) async {
    try {
      final res = await vmServiceClient.invoke('ext.interceptly.ping');
      final buffer = StringBuffer();
      buffer.writeln('Interceptly Status: CONNECTED');
      buffer.writeln('- Connected URI: ${vmServiceClient.connectedUri}');
      buffer.writeln('- Active Isolate: ${vmServiceClient.activeIsolateId}');
      buffer.writeln('- App Name: ${res['appName'] ?? "Unknown"}');
      buffer.writeln('- Extension API Version: ${res['extensionApiVersion']}');
      buffer.writeln(
        '- Total Recorded Requests: ${res['requestCount'] ?? res['entryCount'] ?? 0}',
      );

      final version = res['extensionApiVersion'] as int?;
      if (version != null &&
          (version < minCompatibleExtensionApiVersion ||
              version > maxCompatibleExtensionApiVersion)) {
        buffer.writeln(
          'WARNING: Version mismatch! App is $version, CLI supports '
          '$minCompatibleExtensionApiVersion..$maxCompatibleExtensionApiVersion.',
        );
      }
      return CallToolResult(
        content: [TextContent(text: buffer.toString().trim())],
      );
    } catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Interceptly Status: DISCONNECTED ($e)')],
        isError: true,
      );
    }
  }

  Future<CallToolResult> _handleListRequests(CallToolRequest request) async {
    try {
      final args = <String, String>{};
      if (request.arguments?['since_id'] != null) {
        args['since_id'] = request.arguments!['since_id'].toString();
      }
      if (request.arguments?['status_filter'] case final String statusFilter) {
        args['status_filter'] = statusFilter;
      }
      if (request.arguments?['search'] case final String search) {
        args['search'] = search;
      }
      if (request.arguments?['search_body'] != null) {
        final raw = request.arguments!['search_body'];
        args['search_body'] =
            (raw is bool) ? raw.toString() : raw.toString().toLowerCase();
      }
      final limit = _coerceInt(request.arguments?['limit'], name: 'limit');
      if (limit != null) {
        _requireRange(limit, 1, 100, 'limit');
        args['limit'] = limit.toString();
      }

      final res = await vmServiceClient.invoke(
        'ext.interceptly.listRequests',
        args,
      );
      return CallToolResult(content: [TextContent(text: jsonEncode(res))]);
    } catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Error in list_requests: $e')],
        isError: true,
      );
    }
  }

  Future<CallToolResult> _handleGetRequestDetail(
    CallToolRequest request,
  ) async {
    try {
      final id = request.arguments?['id'];
      if (id == null) {
        return CallToolResult(
          content: [TextContent(text: 'Missing required argument: id')],
          isError: true,
        );
      }

      final args = <String, String>{'id': id.toString()};
      if (request.arguments?['part'] case final String part) {
        args['part'] = part;
      }
      final maxChars = _coerceInt(
        request.arguments?['max_chars'],
        name: 'max_chars',
      );
      if (maxChars != null) {
        _requireRange(maxChars, 1, 100000, 'max_chars');
        args['max_chars'] = maxChars.toString();
      }
      final offset = _coerceInt(request.arguments?['offset'], name: 'offset');
      if (offset != null) {
        _requireRange(offset, 0, 10000000, 'offset');
        args['offset'] = offset.toString();
      }

      final res = await vmServiceClient.invoke(
        'ext.interceptly.getRequestDetail',
        args,
      );
      return CallToolResult(content: [TextContent(text: jsonEncode(res))]);
    } catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Error in get_request_detail: $e')],
        isError: true,
      );
    }
  }

  Future<CallToolResult> _handleListRealtimeFrames(
    CallToolRequest request,
  ) async {
    try {
      final args = <String, String>{};
      if (request.arguments?['session_id'] case final String sessionId) {
        args['session_id'] = sessionId;
      }
      if (request.arguments?['direction'] case final String direction) {
        if (direction != 'all') {
          args['direction'] = switch (direction.toLowerCase()) {
            'sent' => 'outgoing',
            'received' => 'incoming',
            final other => other,
          };
        }
      }
      if (request.arguments?['type'] case final String type) {
        if (type != 'all') {
          args['type'] = type;
        }
      }
      if (request.arguments?['since_id'] case final String sinceId) {
        args['since_id'] = sinceId;
      }
      final frameLimit = _coerceInt(request.arguments?['limit'], name: 'limit');
      if (frameLimit != null) {
        _requireRange(frameLimit, 1, 200, 'limit');
        args['limit'] = frameLimit.toString();
      }

      final res = await vmServiceClient.invoke(
        'ext.interceptly.listRealtimeFrames',
        args,
      );
      return CallToolResult(content: [TextContent(text: jsonEncode(res))]);
    } catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Error in list_realtime_frames: $e')],
        isError: true,
      );
    }
  }

  Future<CallToolResult> _handleGetRealtimeFrameDetail(
    CallToolRequest request,
  ) async {
    try {
      final sessionId = request.arguments?['session_id'];
      final frameId = request.arguments?['frame_id'];
      if (sessionId == null || frameId == null) {
        return CallToolResult(
          content: [
            TextContent(
              text: 'Missing required arguments: session_id and frame_id',
            ),
          ],
          isError: true,
        );
      }

      final args = <String, String>{
        'session_id': sessionId.toString(),
        'frame_id': frameId.toString(),
      };
      final frameMax = _coerceInt(
        request.arguments?['max_chars'],
        name: 'max_chars',
      );
      if (frameMax != null) {
        _requireRange(frameMax, 1, 100000, 'max_chars');
        args['max_chars'] = frameMax.toString();
      }
      final frameOffset = _coerceInt(
        request.arguments?['offset'],
        name: 'offset',
      );
      if (frameOffset != null) {
        _requireRange(frameOffset, 0, 10000000, 'offset');
        args['offset'] = frameOffset.toString();
      }

      final res = await vmServiceClient.invoke(
        'ext.interceptly.getRealtimeFrameDetail',
        args,
      );
      return CallToolResult(content: [TextContent(text: jsonEncode(res))]);
    } catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Error in get_realtime_frame_detail: $e')],
        isError: true,
      );
    }
  }

  Future<CallToolResult> _handleGetTrafficSummary(
    CallToolRequest request,
  ) async {
    try {
      final res = await vmServiceClient.invoke(
        'ext.interceptly.getTrafficSummary',
      );
      return CallToolResult(content: [TextContent(text: jsonEncode(res))]);
    } catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Error in get_traffic_summary: $e')],
        isError: true,
      );
    }
  }

  Future<CallToolResult> _handleSetNetworkSimulation(
    CallToolRequest request,
  ) async {
    if (!allowMutation) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Mutation tools are disabled. Start server with --allow-mutation to enable set_network_simulation and clear_traffic.',
          ),
        ],
        isError: true,
      );
    }

    try {
      final args = <String, String>{};
      if (request.arguments?['profile'] case final String profile) {
        args['profile'] = profile;
      }
      if (request.arguments?['enabled'] != null) {
        final raw = request.arguments!['enabled'];
        final asBool =
            raw is bool ? raw : raw.toString().toLowerCase() == 'true';
        args['enabled'] = asBool.toString();
      }
      if (request.arguments?['offline'] != null) {
        final raw = request.arguments!['offline'];
        final asBool =
            raw is bool ? raw : raw.toString().toLowerCase() == 'true';
        args['offline'] = asBool.toString();
      }
      final latency = _coerceInt(
        request.arguments?['latency_ms'],
        name: 'latency_ms',
      );
      if (latency != null) {
        _requireRange(latency, 0, 60000, 'latency_ms');
        args['latency_ms'] = latency.toString();
      }
      final down = _coerceInt(
        request.arguments?['download_kbps'],
        name: 'download_kbps',
      );
      if (down != null) {
        _requireRange(down, 0, 1000000, 'download_kbps');
        args['download_kbps'] = down.toString();
      }
      final up = _coerceInt(
        request.arguments?['upload_kbps'],
        name: 'upload_kbps',
      );
      if (up != null) {
        _requireRange(up, 0, 1000000, 'upload_kbps');
        args['upload_kbps'] = up.toString();
      }

      final res = await vmServiceClient.invoke(
        'ext.interceptly.setNetworkSimulation',
        args,
      );
      return CallToolResult(content: [TextContent(text: jsonEncode(res))]);
    } catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Error in set_network_simulation: $e')],
        isError: true,
      );
    }
  }

  Future<CallToolResult> _handleClearTraffic(CallToolRequest request) async {
    if (!allowMutation) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Mutation tools are disabled. Start server with --allow-mutation to enable set_network_simulation and clear_traffic.',
          ),
        ],
        isError: true,
      );
    }

    try {
      final res = await vmServiceClient.invoke('ext.interceptly.clearTraffic');
      return CallToolResult(content: [TextContent(text: jsonEncode(res))]);
    } catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Error in clear_traffic: $e')],
        isError: true,
      );
    }
  }

  Future<CallToolResult> _handleExportCurl(CallToolRequest request) async {
    try {
      final id = request.arguments?['id'];
      if (id == null) {
        return CallToolResult(
          content: [TextContent(text: 'Missing required argument: id')],
          isError: true,
        );
      }

      final args = <String, String>{'id': id.toString()};

      final res = await vmServiceClient.invoke(
        'ext.interceptly.exportCurl',
        args,
      );
      final curl = res['curl'] as String? ?? '';
      return CallToolResult(content: [TextContent(text: curl)]);
    } catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Error in export_curl: $e')],
        isError: true,
      );
    }
  }

  Future<CallToolResult> _handleConnectApp(CallToolRequest request) async {
    final uriArg = request.arguments?['uri'];
    if (uriArg == null) {
      return CallToolResult(
        content: [TextContent(text: 'Missing required argument: uri')],
        isError: true,
      );
    }
    final uriStr = uriArg.toString().trim();
    if (uriStr.isEmpty) {
      return CallToolResult(
        content: [TextContent(text: 'Missing required argument: uri')],
        isError: true,
      );
    }

    final parsed = Uri.tryParse(uriStr.trim());
    if (parsed == null || !AppDiscovery.isLoopbackUri(parsed)) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Security error: URI must be a valid loopback address (127.0.0.1 or localhost), got: $uriStr',
          ),
        ],
        isError: true,
      );
    }

    try {
      await vmServiceClient.connect(AppDiscovery.normalizeWsUri(parsed));
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Successfully connected to Flutter app at ${vmServiceClient.connectedUri} '
                '(isolate: ${vmServiceClient.activeIsolateId})',
          ),
        ],
      );
    } catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Failed to connect to $uriStr: $e')],
        isError: true,
      );
    }
  }

  /// Coerces string or numeric MCP arguments to `int`.
  ///
  /// Accepts `int`, numeric strings, and doubles with integral values.
  /// Returns null when [raw] is null so optional arguments stay unset.
  int? _coerceInt(Object? raw, {required String name}) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is double) {
      if (raw == raw.truncateToDouble()) return raw.toInt();
      throw ArgumentError('Invalid integer for $name: $raw');
    }
    final parsed = int.tryParse(raw.toString().trim());
    if (parsed == null) {
      throw ArgumentError('Invalid integer for $name: $raw');
    }
    return parsed;
  }

  /// Validates that [value] lies within `[min, max]`.
  void _requireRange(int value, int min, int max, String name) {
    if (value < min || value > max) {
      throw ArgumentError(
        'Out of range for $name: $value '
        'expected $min..$max',
      );
    }
  }
}
