# Interceptly — Agent Install & Usage Guide

You are integrating Interceptly, a client-agnostic network & realtime traffic
inspector for Flutter, into an existing Flutter project. Follow these steps in
order. Do not skip verification.

## 1. Detect & Confirm Setup (MANDATORY STOP GATE)

Do NOT edit any code or add dependencies yet. First inspect the codebase, then
**STOP and present your findings to the user in a single unified prompt**.

Inspect the project:
- **Networking clients:** Check `pubspec.yaml` for `dio`, `http`, `chopper`,
  `web_socket_channel`, and `socket_io_client` (note each version). Also search imports for raw
  `dart:io` sockets (`Socket`, `WebSocket`, `HttpClient`).
- **Existing inspectors/loggers:** Search for `alice`, `alice_dio`,
  `alice_lightweight`, `talker`, `talker_dio_logger`, `dio_log`,
  `http_logger`, `pretty_dio_logger`, `chopper_logger`, or custom debug overlays.
  List every match with file paths.
- **Navigation & Entry:** Find where `runApp` / `MaterialApp` (or `MaterialApp.router` /
  `GoRouter`) is built and whether a global `navigatorKey` exists.
- **Active AI Coding Assistant:** Check which AI assistant or IDE is currently in use:
  - Antigravity: check for `~/.gemini/antigravity-ide/mcp_config.json` or `.agents/`.
  - Cursor: check for workspace `.cursor/` or `~/.cursor/mcp.json`.
  - Claude Desktop: check for Claude Desktop config directory.
  - Claude Code: check for `~/.claude.json` or `claude` CLI.
  - Windsurf: check for `~/.codeium/windsurf/mcp_config.json`.
  - VS Code (Cline / Roo Code): check for `.vscode/` or active extension settings.

**STOP AND ASK THE USER UPFRONT (Do not split this into multiple steps):**
1. **REST Traffic:** Which detected REST clients (`dio`, `http`, `chopper`) should be intercepted?
2. **Realtime / Socket Traffic:** Confirm whether to intercept WebSockets/sockets or Socket.IO now (default: yes if `web_socket_channel`, `dart:io.WebSocket`, or `socket_io_client` detected; ask if none detected).
3. **Existing Inspectors:** If any old logger/inspector was detected, ask to remove it (recommended to avoid duplicate capture overhead and UI overlay conflicts) or keep side-by-side.
4. **Flavors / Environment:** Confirm in which modes to enable (default: everywhere except production release).
5. **AI Assistant & MCP Integration (`interceptly_mcp`):** Ask upfront: *"Do you want to enable Model Context Protocol (MCP) so your AI assistant can inspect network traffic, diagnose errors, and export cURL directly in chat?"* If yes, confirm their AI assistant (Cursor, Antigravity, Claude Desktop, Windsurf, VS Code / Cline) so you can automatically configure the MCP settings file for them.

**Only proceed to Step 2 once the user has answered all questions.**

## 2. Add dependencies (hosted only)

```bash
flutter pub add interceptly
```

Then add only the adapters for the client list the user confirmed in step 1
(`flutter pub add` resolves the latest compatible version; do not pin
versions here so this guide stays correct across releases):

```bash
flutter pub add interceptly_dio         # if dio is used
flutter pub add interceptly_http        # if package:http is used
flutter pub add interceptly_chopper     # if chopper is used
flutter pub add interceptly_web_socket  # if web_socket_channel is used
flutter pub add interceptly_socket_io   # if socket_io_client is used
```

If the user agreed to install MCP in Step 1, also activate the standalone MCP CLI globally:

```bash
dart pub global activate interceptly_mcp
```


Rules:

- Never use `path:` dependencies for these packages in a consumer app.
- Never downgrade the app's existing `dio` / `http` / `chopper` /
  `web_socket_channel` / `socket_io_client` versions to satisfy adapters; report a conflict instead.

## 3. Wire `Interceptly.init` (debug/profile only)

Ask the user first: most projects use flavors (dev/staging/prod). Confirm in
which flavors the inspector should be enabled — default recommendation is
everywhere except production store builds. If the project defines its own
`isDev` / `isStaging` flags or `--dart-define` environment markers, use those
instead of (or in addition to) the `kDebugMode || kProfileMode` check below,
and state which condition you chose.

- Ensure a global key exists: `final navigatorKey = GlobalKey<NavigatorState>();`
- Pass it to `MaterialApp` (`navigatorKey:`) or to `GoRouter` (`navigatorKey:`).
- Only if the floating button disappears after route transitions, additionally set `navigatorObservers: [Interceptly.navigatorObserver]` on `MaterialApp`. Do not present this as the default setup.
- After `runApp`, initialize only in debug/profile:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp(navigatorKey: navigatorKey));

  if (kDebugMode || kProfileMode) {
    Interceptly.init(
      navigatorKey: navigatorKey,
      settings: const InterceptlySettings(maxEntries: 1000),
    );
  }
}
```

- The SDK has no release guard: `Interceptly.init` works in any build mode, so always wrap it in `if (kDebugMode || kProfileMode)` or the inspector ships to production users.

## 4. Attach adapters

Dio:

```dart
import 'package:interceptly_dio/interceptly_dio.dart';

final dio = Dio()..interceptors.add(InterceptlyDioInterceptor());
```

`package:http`:

```dart
import 'package:http/http.dart' as http;
import 'package:interceptly_http/interceptly_http.dart';

final client = InterceptlyHttpClient(http.Client());
```

Chopper:

```dart
import 'package:interceptly_chopper/interceptly_chopper.dart';

final chopper = ChopperClient(
  interceptors: [InterceptlyChopperInterceptor()],
);
```

WebSocket (`web_socket_channel` or raw `dart:io.WebSocket`):

```dart
import 'package:interceptly_web_socket/interceptly_web_socket.dart';

// Option A: Direct connect
final channel = InterceptlyWebSocketChannel.connect(
  Uri.parse('wss://example.com/socket'),
);

// Option B: Wrap an existing WebSocketChannel (or IOWebSocketChannel for dart:io.WebSocket)
final channel = InterceptlyWebSocketChannel(existingChannel);
```

Socket.IO (`package:socket_io_client`):

```dart
import 'package:interceptly_socket_io/interceptly_socket_io.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

final socket = io.io('https://example.com/socket.io');

// Option A: Extension method
socket.attachInterceptly();

// Option B: Static helper
final tracker = InterceptlySocketIo.attach(socket);

socket.connect();
```

Optional: skip noisy URLs so they cost zero memory/disk:

```dart
InterceptlySettings(
  shouldCapture: (url) =>
      !url.contains('/health-check') && !url.contains('/analytics'),
)
```

`shouldCapture` runs synchronously per request: keep it fast and non-blocking.

## 5. Configure AI Assistant MCP Server (Automatic File Update)

If the user agreed to install MCP in Step 1, **you (the agent) must automatically update their AI assistant's MCP configuration file**. Do NOT instruct the user to manually edit JSON files unless access is restricted.

### 5.1 Locate the Config File

Identify the config file path based on the detected or confirmed AI assistant:

| AI Assistant / IDE | Scope | Config File Path |
|--------------------|-------|------------------|
| **Cursor** | Workspace | `<project-root>/.cursor/mcp.json` |
| | Global | `~/.cursor/mcp.json` |
| **Antigravity / Gemini** | Global | `~/.gemini/antigravity-ide/mcp_config.json` |
| | Workspace | `<project-root>/.agents/mcp_config.json` |
| **Windsurf** | Global | `~/.codeium/windsurf/mcp_config.json` |
| | Workspace | `<project-root>/.windsurf/mcp.json` |
| **Claude Desktop** | macOS | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| | Windows | `%APPDATA%\Claude\claude_desktop_config.json` |
| | Linux | `~/.config/Claude/claude_desktop_config.json` |
| **Claude Code (CLI)** | Global | Run `claude mcp add interceptly dart pub global run interceptly_mcp --allow-mutation` |
| **VS Code (Cline)** | Global | `~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json` |
| **VS Code (Roo Code)**| Global | `~/Library/Application Support/Code/User/globalStorage/rooveterinaryinc.roo-cline/settings/cline_mcp_settings.json` |
| **VS Code (General)** | Workspace | `<project-root>/.vscode/mcp.json` |

*Tip: For workspace-specific setups (Cursor, Antigravity, VS Code), preferring project-local files (`.cursor/mcp.json`, `.vscode/mcp.json`) ensures the configuration is immediately available to anyone opening the project.*

### 5.2 Merge Configuration

1. Read the existing config file (or create it with `{"mcpServers": {}}` if missing).
2. Cleanly merge the `"interceptly"` server definition into `"mcpServers"` while **preserving all existing servers**:

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

3. Save the file and inform the user of the updated file path.

## 6. Verify

1. Run `flutter analyze` — zero new issues from these changes.
2. Run the app, trigger one request per attached client.
3. Open the inspector via the floating button and confirm one row per request,
   with request/response bodies visible.
4. If a row is missing, check `shouldCapture` and confirm the right adapter
   wraps the client that actually performs the call.
5. If MCP was enabled:
   - Run `dart pub global run interceptly_mcp --version` to verify CLI installation.
   - In your AI assistant chat, verify the connection using the `ping` tool or prompt: *"Check if Interceptly is connected"*.

## 7. Everyday usage (for the developer)

- Browse/filter traffic in the inspector overlay; tap a row for detail tabs.
- Replay: edit headers/body in the detail page and re-send.
- Export a record as HAR, cURL, or Postman collection from the detail page.
- Simulate conditions via `Interceptly.instance.setNetworkSimulation(...)`
  (Offline, Slow 3G, Fast 3G, 4G, Wi-Fi, custom profiles).
- Programmatic control: `Interceptly.showInspector(context)`,
  `Interceptly.hideFloatingButtonForSession()` /
  `Interceptly.showFloatingButtonForSession()`, `Interceptly.detach()`.
- **AI-Powered Debugging:** Ask your AI assistant to diagnose network errors (*"Why did the last request fail?"*), export cURL commands, inspect realtime WebSocket frames, or simulate network latency directly in chat.

## 8. Troubleshooting

- Inspector opens in release builds too if `init` was called there: the SDK has no release guard, so the `kDebugMode || kProfileMode` wrapper at the call site is the only protection.
- Floating button disappears after navigation: `navigatorObservers` is missing.
- iOS simulator build fails on deployment target: the app needs
  `platform :ios, '15.0'` (current Xcode supports 15.0+ only).
- Developing against a local Interceptly checkout: use
  `pubspec_overrides.yaml` with `path:` overrides (melos generates these);
  never commit `path:` deps in a consumer app.
- AI assistant cannot connect to app: ensure the Flutter app is running in debug mode with `Interceptly.init()` called, and that `127.0.0.1` loopback access is available.