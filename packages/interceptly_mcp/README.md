# interceptly_mcp

Standalone Model Context Protocol (MCP) server for the [Interceptly](https://pub.dev/packages/interceptly) Flutter network inspector.

Connects AI coding assistants (Cursor, Claude Desktop, Antigravity, Windsurf) directly to running Flutter applications over the standard Dart VM Service protocol.

---

## Architecture & Zero-App-Footprint Design

Unlike traditional inspector plugins that embed HTTP servers inside Flutter apps, `interceptly_mcp` adopts an out-of-process architecture:

1. **Inside the Flutter App (`package:interceptly`):**
   - In debug mode (`kDebugMode`), `Interceptly.init()` registers standard Dart VM Service Protocol extensions (`ext.interceptly.*` via `dart:developer`).
   - Zero additional network listener ports, zero embedded HTTP server overhead, and zero attack surface in release builds.
   - Registration is idempotent and safe across Hot Reload and Hot Restart.

2. **Standalone MCP CLI (`package:interceptly_mcp`):**
   - An independent pure Dart CLI executable running on your developer machine.
   - Communicates with AI coding assistants over `stdio` using official `package:dart_mcp`.
   - Connects to the running Flutter app's VM Service WebSocket via Dart Tooling Daemon (DTD) or explicit `--uri`.
   - Protects `stdout` against log pollution using `runZonedGuarded` with `ZoneSpecification(print: ...) -> stderr`.

---

## Installation

Install globally using `dart pub`:

```bash
dart pub global activate interceptly_mcp
```

Or run directly from the monorepo workspace:

```bash
dart run packages/interceptly_mcp/bin/interceptly_mcp.dart
```

---

## Configuration

### Cursor

Add to your `~/.cursor/mcp.json` (or `.cursor/mcp.json` in your workspace):

```json
{
  "mcpServers": {
    "interceptly": {
      "command": "dart",
      "args": [
        "pub",
        "global",
        "run",
        "interceptly_mcp",
        "--allow-mutation"
      ]
    }
  }
}
```

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows):

```json
{
  "mcpServers": {
    "interceptly": {
      "command": "dart",
      "args": [
        "pub",
        "global",
        "run",
        "interceptly_mcp",
        "--allow-mutation"
      ]
    }
  }
}
```

---

## CLI Options

```
Usage: interceptly_mcp [options]
-u, --uri               Explicit Flutter app VM Service WebSocket URI (e.g. ws://127.0.0.1:54321/ws)
-d, --dtd-uri           Explicit Dart Tooling Daemon (DTD) URI for automatic discovery
    --allow-mutation    Allow mutating tools (set_network_simulation, clear_traffic)
-h, --help              Show usage information
-v, --version           Show version information
```

### Environment Variables

- `INTERCEPTLY_VM_SERVICE_URI`: Fallback WebSocket URI if `--uri` is not passed.
- `DTD_URI`: Fallback DTD WebSocket URI for automatic candidate discovery.

---

## Available Tools

| Tool | Description | Mutation Required |
|---|---|:---:|
| `ping` | Checks connection status, app name, isolate ID, entry count, and version contract compatibility. | No |
| `list_requests` | Lists recorded requests with optional `status_filter` (`all`, `failed`, `2xx`, `3xx`, `4xx`, `5xx`), `search` query, and `since_id` cursor pagination. | No |
| `get_request_detail` | Retrieves detailed information (headers, body, timings) with `part` selection, `offset`, and `max_chars` truncation. | No |
| `list_realtime_frames` | Lists recorded WebSocket and Realtime frames with optional filtering by `session_id`, `direction` (sent/received), `type` (text/binary/ping/pong/close), and `since_id`. | No |
| `get_realtime_frame_detail` | Retrieves detailed payload content and metadata for a specific WebSocket/Realtime frame with `offset` and `max_chars` pagination. | No |
| `get_traffic_summary` | Provides a quick snapshot of overall network metrics: total requests, failure rate, status distribution, latency percentiles (p50/p90/p95/p99), bandwidth, and active realtime sessions. | No |
| `export_curl` | Exports a recorded network request as a replayable cURL command. | No |
| `connect_app` | Explicitly binds to a loopback VM Service URI when multiple Flutter apps are active. | No |
| `set_network_simulation` | Simulates network latency and error conditions on the connected app. | **Yes** (`--allow-mutation`) |
| `clear_traffic` | Clears all recorded network requests and resets memory/disk buffers. | **Yes** (`--allow-mutation`) |

---

## Security Safeguards

1. **Loopback Address Enforcement:**
   `interceptly_mcp` strictly validates all target URIs against `127.0.0.1`, `localhost`, and `::1`. Remote hosts and external IP addresses are rejected with `Security error`.
2. **Opt-in Mutation Guard:**
   Destructive actions (`set_network_simulation`, `clear_traffic`) require `--allow-mutation`. Without this flag, requests fail with a clear diagnostic message.
3. **Stdio Isolation:**
   All diagnostic logs and library `print()` calls are redirected to `stderr`, guaranteeing that `stdout` contains only well-formed JSON-RPC frames.

---

## Manual Verification Checklist (Flutter Hot Restart)

1. Launch your Flutter app in debug mode:
   ```bash
   flutter run
   ```
2. Note the printed VM Service WebSocket URI (or let DTD discover it automatically).
3. Connect your MCP client or launch `interceptly_mcp`:
   ```bash
   dart run packages/interceptly_mcp/bin/interceptly_mcp.dart --uri <ws-uri>
   ```
4. Query traffic using `list_requests`.
5. Press `R` in the Flutter console to perform a **Hot Restart**.
6. Query traffic again using `list_requests`:
   - Notice that `interceptly_mcp` detects isolate invalidation, automatically discovers the new isolate, and returns traffic without crashing.
