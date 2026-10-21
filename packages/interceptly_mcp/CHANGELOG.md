## 1.0.0

Initial release of `interceptly_mcp`, the Model Context Protocol (MCP) server for Interceptly.

- Pure Dart standalone MCP CLI connecting AI coding assistants (Cursor, Claude Desktop, Antigravity, Windsurf) to running Flutter applications.
- Communicates over stdio using official `package:dart_mcp`.
- Connects to Flutter app VM Service over loopback WebSockets via Dart Tooling Daemon (DTD) or explicit `--uri`.
- 10 tools implemented:
  - `ping`: Health check, app details, isolate info, and version contract compatibility.
  - `list_requests`: HTTP traffic listing with status filtering, multi-phase search, and cursor pagination.
  - `get_request_detail`: Detailed HTTP request/response payloads with truncation.
  - `list_realtime_frames`: WebSocket and realtime frame stream listing.
  - `get_realtime_frame_detail`: Realtime frame inspection with base64 binary support.
  - `get_traffic_summary`: Snapshot metrics (failure rate, status codes, latency percentiles, bandwidth).
  - `export_curl`: Replayable cURL command export.
  - `connect_app`: Dynamic VM Service binding for multi-app scenarios.
  - `set_network_simulation`: Latency and error simulation on connected apps (requires `--allow-mutation`).
  - `clear_traffic`: Resets in-memory and disk traffic buffers (requires `--allow-mutation`).
- Resilient Hot Restart handling with automatic isolate invalidation recovery.
- Strict security guards enforcing loopback address binding.
