# Interceptly — Agent Install & Usage Guide

You are integrating Interceptly, a client-agnostic network & realtime traffic
inspector for Flutter, into an existing Flutter project. Follow these steps in
order. Do not skip verification. Reply to the user in the language they are
writing in.

## Ground rules

- **Ask with your question tool, not with prose.** Every question in this guide
  must be asked through your interactive question tool (e.g. `AskUserQuestion`
  in Claude Code, or your IDE's equivalent choice UI). Plain-text questions in
  a long reply are easy to miss.
  - Use selectable options, with the default labelled "(Recommended)".
  - Use multi-select where several answers can apply.
  - Batch questions into as few tool calls as the tool allows.
  - If your environment has no question tool, print a short numbered list of
    the questions, then **END YOUR TURN and wait**. Never continue with assumed
    defaults.
  - If no user is available to answer, change nothing and report what you
    detected.
- **Never touch files outside the project** (e.g. `~/.cursor/mcp.json`,
  `~/.claude.json`) without explicit consent given through the question tool.
- **Never use `path:` dependencies** for Interceptly packages in a consumer
  app.
- **Never downgrade** the app's existing `dio` / `http` / `chopper` /
  `web_socket_channel` / `socket_io_client` versions to satisfy adapters.
  Report the conflict instead.

## 1. Detect & confirm (MANDATORY STOP GATE)

Do NOT edit any code or add dependencies yet. First inspect the codebase, then
stop and ask the user.

Inspect the project:

- **Networking clients:** check `pubspec.yaml` for `dio`, `http`, `chopper`,
  `web_socket_channel`, and `socket_io_client` (note each version). Retrofit
  runs on top of `dio`, so treat it as `dio`. Also search imports for raw
  `dart:io` sockets (`Socket`, `WebSocket`, `HttpClient`).
- **Where clients are created:** find the real instantiation points (DI
  containers such as `get_it` / `injectable`, Riverpod/Bloc providers, API
  service classes). Adapters in step 5 must be attached there, not to new
  instances.
- **Existing inspectors/loggers:** search for `alice`, `alice_dio`,
  `alice_lightweight`, `talker`, `talker_dio_logger`, `dio_log`,
  `http_logger`, `pretty_dio_logger`, `chopper_logger`, or custom debug
  overlays. List every match with file paths.
- **Navigation & entry:** find where `runApp` / `MaterialApp` (or
  `MaterialApp.router` / `GoRouter`) is built and whether a global
  `navigatorKey` exists.
- **Flavors / environment markers:** look for flavors (dev/staging/prod),
  `isDev` / `isStaging` flags, or `--dart-define` markers.
- **Your own host:** you are the AI assistant that will be configured for MCP.
  Identify which one you are (Cursor, Claude Code, Claude Desktop, Antigravity,
  Windsurf, VS Code with Cline / Roo Code / Copilot).

### Questions (ask them together, via the question tool)

1. **What to intercept** (multi-select): the detected REST clients (`dio`,
   `http`, `chopper`) and realtime clients (WebSocket, Socket.IO). Pre-select
   everything detected. If no realtime client was detected, leave it
   unselected.
2. **Where to enable the inspector:** options such as "Everywhere except
   production store builds (Recommended)", "Debug and profile only", "Specific
   flavors" (the user names them).
3. **Existing inspector** (ask only if one was detected): "Remove it
   (Recommended, avoids duplicate capture and overlay conflicts)" or "Keep it
   side by side".
4. **MCP for your AI assistant (`interceptly_mcp`):** "No MCP", "Yes,
   read-only (Recommended)", "Yes, allow mutations" (lets the AI replay
   requests and change network simulation, adds `--allow-mutation`). State
   which assistant you will configure, and let the user pick another via
   "Other".

**Only proceed to step 2 once the user has answered.**

## 2. Preflight & dependencies

Preflight:

1. Run `flutter analyze` **before changing anything** and note the result as a
   baseline.
2. Check iOS: the app needs `platform :ios, '15.0'` in `ios/Podfile` (and a
   matching deployment target in Xcode). Raise it if lower and tell the user.

Add dependencies (hosted only; `flutter pub add` resolves the latest
compatible version, so do not pin versions here):

```bash
flutter pub add interceptly
```

Then add only the adapters for the clients confirmed in step 1:

```bash
flutter pub add interceptly_dio         # if dio is used
flutter pub add interceptly_http        # if package:http is used
flutter pub add interceptly_chopper     # if chopper is used
flutter pub add interceptly_web_socket  # if web_socket_channel is used
flutter pub add interceptly_socket_io   # if socket_io_client is used
```

If the user chose MCP, activate the standalone MCP CLI globally:

```bash
dart pub global activate interceptly_mcp
```

## 3. Remove the old inspector (only if the user chose "Remove")

For each match listed in step 1:

1. Remove its interceptor / wrapper from every client it was attached to.
2. Remove its overlay, shake/button trigger, and any `navigatorKey` it
   required, **reusing** the existing key if the app already needs one.
3. Remove the dependency with `flutter pub remove <package>` and delete
   now-unused imports and files.
4. Run `flutter analyze` to confirm nothing still references it.

## 4. Wire `Interceptly.init`

Use the condition the user confirmed in step 1. Define it **once** and reuse it
for both `init` and adapter attachment:

```dart
// lib/interceptly_config.dart
import 'package:flutter/foundation.dart';

/// Default: debug + profile. Replace with the project's own flavor /
/// --dart-define condition if the user chose a different mode in step 1,
/// and tell the user which condition you used.
const bool interceptlyEnabled = kDebugMode || kProfileMode;
```

- Ensure a global key exists: `final navigatorKey = GlobalKey<NavigatorState>();`
- Pass it to `MaterialApp` (`navigatorKey:`) or to `GoRouter` (`navigatorKey:`).
- Only if the floating button disappears after route transitions, additionally
  set `navigatorObservers: [Interceptly.navigatorObserver]` on `MaterialApp`.
  Do not present this as the default setup.
- Initialize after `runApp`:

```dart
import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';

import 'interceptly_config.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp(navigatorKey: navigatorKey));

  if (interceptlyEnabled) {
    Interceptly.init(
      navigatorKey: navigatorKey,
      settings: const InterceptlySettings(maxEntries: 1000),
    );
  }
}
```

**The SDK has no release guard.** `Interceptly.init` works in any build mode,
so the `if (interceptlyEnabled)` wrapper is the only thing keeping the
inspector out of production builds. Never call `init` without it.

## 5. Attach adapters

Attach adapters to the **existing** client instances found in step 1 (DI
registrations, providers, API classes). Do not create parallel clients. Gate
each attachment with the same `interceptlyEnabled` flag.

Dio (also covers Retrofit):

```dart
import 'package:interceptly_dio/interceptly_dio.dart';

final dio = Dio();
if (interceptlyEnabled) {
  // Recommended: Transport adapter (order-independent, captures after auth interceptors
  // and before response transformers mutate data into domain models)
  dio.useInterceptly();

  // Alternative (if transport adapter cannot be swapped):
  // dio.interceptors.add(InterceptlyDioInterceptor());
}
```

`package:http`:

```dart
import 'package:http/http.dart' as http;
import 'package:interceptly_http/interceptly_http.dart';

final http.Client client =
    interceptlyEnabled ? InterceptlyHttpClient(http.Client()) : http.Client();
```

Chopper:

```dart
import 'package:interceptly_chopper/interceptly_chopper.dart';

final chopper = ChopperClient(
  interceptors: [
    if (interceptlyEnabled) InterceptlyChopperInterceptor(),
  ],
);
```

WebSocket (`web_socket_channel` or raw `dart:io.WebSocket`):

```dart
import 'package:interceptly_web_socket/interceptly_web_socket.dart';

// Option A: direct connect
final channel = interceptlyEnabled
    ? InterceptlyWebSocketChannel.connect(Uri.parse('wss://example.com/socket'))
    : WebSocketChannel.connect(Uri.parse('wss://example.com/socket'));

// Option B: wrap an existing WebSocketChannel
// (or IOWebSocketChannel for dart:io.WebSocket)
final wrapped =
    interceptlyEnabled ? InterceptlyWebSocketChannel(existingChannel) : existingChannel;
```

Socket.IO (`package:socket_io_client`):

```dart
import 'package:interceptly_socket_io/interceptly_socket_io.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

final socket = io.io('https://example.com/socket.io');

if (interceptlyEnabled) {
  // Option A: extension method
  socket.attachInterceptly();

  // Option B: static helper
  // final tracker = InterceptlySocketIo.attach(socket);
}

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

## 6. Configure the AI assistant's MCP server (only if the user chose MCP)

You (the agent) update the MCP configuration file yourself. Do not tell the
user to edit JSON by hand unless file access is restricted.

### 6.1 Pick the file and scope

Default to the assistant you are running in. **Prefer project-local config.**
Only write a global file after the user explicitly agrees (ask with the
question tool). Some assistants only support global config; for those, ask
before writing.

| Assistant | Scope | Config file |
|-----------|-------|-------------|
| **Cursor** | Project | `<project-root>/.cursor/mcp.json` |
| | Global | `~/.cursor/mcp.json` |
| **Antigravity / Gemini** | Project | `<project-root>/.agents/mcp_config.json` |
| | Global | `~/.gemini/antigravity-ide/mcp_config.json` |
| **Windsurf** | Project | `<project-root>/.windsurf/mcp.json` |
| | Global | `~/.codeium/windsurf/mcp_config.json` |
| **Claude Desktop** | Global (macOS) | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| | Global (Windows) | `%APPDATA%\Claude\claude_desktop_config.json` |
| | Global (Linux) | `~/.config/Claude/claude_desktop_config.json` |
| **Claude Code (CLI)** | Project / user | use the CLI command in 6.3 |
| **VS Code (native MCP)** | Project | `<project-root>/.vscode/mcp.json` (**different schema**, see 6.3) |
| **VS Code (Cline)** | Global (macOS) | `~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json` |
| | Global (Windows) | `%APPDATA%\Code\User\globalStorage\saoudrizwan.claude-dev\settings\cline_mcp_settings.json` |
| | Global (Linux) | `~/.config/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json` |
| **VS Code (Roo Code)** | Global | same as Cline, with the folder `rooveterinaryinc.roo-cline` instead of `saoudrizwan.claude-dev` |

If you write a project-local file, tell the user it is shareable through git:
teammates also need `dart pub global activate interceptly_mcp`, and the
`--allow-mutation` choice would apply to them too. Offer to add the file to
`.gitignore` if they do not want to share it.

### 6.2 Server arguments

- Read-only (default): `dart pub global run interceptly_mcp`
- Mutations allowed (only if the user chose it in step 1): append
  `--allow-mutation`

### 6.3 Merge, never overwrite

For JSON files using `mcpServers` (Cursor, Antigravity, Windsurf, Claude
Desktop, Cline, Roo Code):

1. Read the existing file (create it with `{"mcpServers": {}}` if missing).
2. Merge the `interceptly` entry while **preserving every existing server**:

```json
{
  "mcpServers": {
    "interceptly": {
      "command": "dart",
      "args": ["pub", "global", "run", "interceptly_mcp"]
    }
  }
}
```

(Add `"--allow-mutation"` to `args` only if the user chose it.)

For **VS Code native** (`.vscode/mcp.json`), the top-level key is `servers`,
not `mcpServers`:

```json
{
  "servers": {
    "interceptly": {
      "type": "stdio",
      "command": "dart",
      "args": ["pub", "global", "run", "interceptly_mcp"]
    }
  }
}
```

For **Claude Code**, use the CLI. Note the `--` separator, which stops the
Claude CLI from parsing the server's own flags:

```bash
claude mcp add -s project interceptly -- dart pub global run interceptly_mcp
# with mutations (only if chosen):
# claude mcp add -s project interceptly -- dart pub global run interceptly_mcp --allow-mutation
```

(`-s user` for a global entry, only with the user's consent.)

3. Save the file and tell the user the exact path you changed.

## 7. Verify

1. Run `flutter analyze` and compare with the baseline from step 2: **no new
   issues** from your changes.
2. Run the app and trigger one request per attached client. If you cannot run
   the app in your environment, tell the user exactly what to run and check.
3. Open the inspector via the floating button and confirm one row per request,
   with request/response bodies visible.
4. If a row is missing, check `shouldCapture` and confirm the adapter wraps the
   client instance that actually performs the call.
5. Confirm a release/production-configured build does not initialize the
   inspector (the `interceptlyEnabled` condition is false there).
6. If MCP was enabled:
   - Run `dart pub global run interceptly_mcp --version` to verify the CLI.
   - In the assistant chat, verify the connection with the `ping` tool or ask:
     *"Check if Interceptly is connected"*. Some assistants need a restart or
     an MCP refresh before the new server appears; tell the user if so.

## 8. Everyday usage (for the developer)

- Browse/filter traffic in the inspector overlay; tap a row for detail tabs.
- Replay: edit headers/body in the detail page and re-send.
- Export a record as HAR, cURL, or Postman collection from the detail page.
- Simulate conditions via `Interceptly.instance.setNetworkSimulation(...)`
  (Offline, Slow 3G, Fast 3G, 4G, Wi-Fi, custom profiles).
- Programmatic control: `Interceptly.showInspector(context)`,
  `Interceptly.hideFloatingButtonForSession()` /
  `Interceptly.showFloatingButtonForSession()`, `Interceptly.detach()`.
- **AI-powered debugging:** ask your assistant to diagnose network errors
  (*"Why did the last request fail?"*), export cURL commands, inspect realtime
  WebSocket frames, or simulate network latency directly in chat.

## 9. Troubleshooting

- Inspector shows up in release builds: `init` ran without the
  `interceptlyEnabled` guard (the SDK has no release guard of its own).
- Floating button disappears after navigation: `navigatorObservers` is missing.
- iOS build fails on deployment target: set `platform :ios, '15.0'` in the
  Podfile and the Xcode deployment target.
- Rows missing for one client: the adapter is attached to a different instance
  than the one making the call (check DI / provider registrations).
- Developing against a local Interceptly checkout: add `path:` overrides in your
  app's own `pubspec_overrides.yaml` (this repo's pub workspace no longer
  generates them); never commit `path:` deps in a consumer app.
- AI assistant cannot connect to the app: ensure the Flutter app is running
  with `Interceptly.init()` called and that `127.0.0.1` loopback access is
  available.
- MCP server not listed in the assistant: check that `dart` is on the PATH the
  assistant uses, and restart the assistant after editing its config.