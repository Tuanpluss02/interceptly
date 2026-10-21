# interceptly_mcp

[![pub package](https://img.shields.io/pub/v/interceptly_mcp.svg)](https://pub.dev/packages/interceptly_mcp)
[![pub points](https://img.shields.io/pub/points/interceptly_mcp)](https://pub.dev/packages/interceptly_mcp/score)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE)

Standalone Model Context Protocol (MCP) server for [Interceptly](https://pub.dev/packages/interceptly) Flutter network inspector.

Connects AI coding assistants (**Cursor, Claude Desktop, Antigravity, Windsurf, VS Code**) directly to running Flutter applications over standard Dart VM Service protocols.

---

## Quick Start

### Step 1: In your Flutter App

Add `interceptly` to your project:

```bash
flutter pub add interceptly
# Add adapters as needed (e.g. Dio):
flutter pub add interceptly_dio
```

Initialize in `main.dart` with your app's `navigatorKey`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';
import 'package:dio/dio.dart';
import 'package:interceptly_dio/interceptly_dio.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(MaterialApp(navigatorKey: navigatorKey, home: const MyApp()));

  if (kDebugMode) {
    Interceptly.init(navigatorKey: navigatorKey);
  }
}

// Attach adapter to your HTTP client
final dio = Dio()..interceptors.add(InterceptlyDioInterceptor());
```

Run your app in debug mode (`flutter run`).

---

### Step 2: Install MCP CLI

```bash
dart pub global activate interceptly_mcp
```

---

### Step 3: Add to your AI Assistant

Add to your MCP config (**Cursor** `mcp.json`, **Claude Desktop** `claude_desktop_config.json`, or **VS Code / Windsurf**):

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

> **Auto-Discovery:** Automatically connects to your running Flutter app. No `--uri` needed when running a single app.
>
> **`--allow-mutation`:** Enables modifying tools (`set_network_simulation`, `clear_traffic`). Omit for read-only mode.

---

## How to Talk to AI (Example Prompts)

Once connected, you can ask your AI assistant questions in natural language:

| Goal | Example Prompt in Cursor / Claude | Tool Called by AI |
|---|---|---|
| **Diagnose API failures** | *"Check why my latest checkout API call returned a 4xx/5xx error."* | `list_requests`, `get_request_detail` |
| **Inspect request/response** | *"Show me the request payload and response body for `/api/v1/auth/login`."* | `get_request_detail` |
| **Replay & Debug** | *"Export the last failed request as a cURL command so I can test it in terminal."* | `export_curl` |
| **Inspect WebSockets** | *"List the last 10 WebSocket frames sent or received on the chat session."* | `list_realtime_frames`, `get_realtime_frame_detail` |
| **Network metrics** | *"Summarize the app network traffic: total calls, failure rate, and p90 latency."* | `get_traffic_summary` |
| **Simulate slow network** | *"Simulate Slow 3G network conditions with 1500ms latency to test skeleton loading."* | `set_network_simulation` |
| **Clear traffic** | *"Clear all recorded network traffic logs."* | `clear_traffic` |

---

## Available Tools Reference

| Tool | Description | Requires `--allow-mutation` |
|---|---|:---:|
| `ping` | Checks connection status, app name, isolate ID, entry count, and version compatibility. | No |
| `list_requests` | Lists HTTP traffic with optional `status_filter` (`all`, `failed`, `2xx`, `3xx`, `4xx`, `5xx`), `search` query, and `since_id` cursor pagination. | No |
| `get_request_detail` | Retrieves detailed information (headers, body, timings) with `part` selection, `offset`, and `max_chars` truncation. | No |
| `list_realtime_frames` | Lists recorded WebSocket and Realtime frames with optional filtering by `session_id`, `direction` (sent/received), `type`, and `since_id`. | No |
| `get_realtime_frame_detail` | Retrieves payload content and metadata for a specific WebSocket/Realtime frame with offset and truncation. | No |
| `get_traffic_summary` | Provides snapshot metrics: total requests, failure rate, status distribution, latency percentiles (p50/p90/p95/p99), and bandwidth. | No |
| `export_curl` | Exports a recorded network request as a replayable cURL command. | No |
| `connect_app` | Explicitly binds to a loopback VM Service URI when multiple Flutter apps are active simultaneously. | No |
| `set_network_simulation` | Simulates network latency and error conditions on the connected Flutter app. | **Yes** |
| `clear_traffic` | Clears all recorded network requests and resets memory and disk buffers. | **Yes** |

---

## CLI Options & Discovery Cascade

```
Usage: interceptly_mcp [options]
-u, --uri               Explicit Flutter app VM Service WebSocket URI (e.g. ws://127.0.0.1:54321/ws)
-d, --dtd-uri           Explicit Dart Tooling Daemon (DTD) URI for automatic discovery
    --allow-mutation    Allow mutating tools (set_network_simulation, clear_traffic)
-h, --help              Show usage information
-v, --version           Show version information
```

### Connection Cascade

`interceptly_mcp` resolves target Flutter applications in the following order:

1. Explicit `--uri` CLI parameter.
2. `INTERCEPTLY_VM_SERVICE_URI` environment variable.
3. Active **Dart Tooling Daemon (DTD)** session registration.
4. Local Dart process scanning (`127.0.0.1` DDS endpoints).

If multiple Flutter apps with Interceptly are running simultaneously, `interceptly_mcp` lists all detected candidates and prompts you to select one via `--uri` or the `connect_app` tool.

---

## Security Safeguards

1. **Loopback Address Enforcement:**
   `interceptly_mcp` strictly validates all target URIs against `127.0.0.1`, `localhost`, and `::1`. Remote hosts and external IP addresses are rejected immediately.
2. **Opt-in Mutation Guard:**
   Destructive actions (`set_network_simulation`, `clear_traffic`) require `--allow-mutation`. Without this flag, requests fail with a clear diagnostic message.
3. **Stdio Isolation:**
   All diagnostic logs and library `print()` calls are redirected to `stderr`, guaranteeing that `stdout` contains only well-formed JSON-RPC frames.

---

## Flutter Hot Restart Resilience

`interceptly_mcp` is designed to survive Flutter Hot Restarts seamlessly:

1. When you press `R` in your Flutter terminal, the target isolate is collected/terminated.
2. Rather than crashing the MCP connection, `interceptly_mcp` catches `Sentinel/Collected` errors, queries the VM Service for the freshly spawned isolate, and binds automatically.
3. Your AI assistant maintains an uninterrupted inspection session without needing a restart.

