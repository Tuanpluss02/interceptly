# Interceptly MCP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `interceptly_mcp` as a standalone, zero-bloat Dart CLI MCP Server that inspects live Flutter app traffic and controls network simulation via Dart VM Service protocol extensions (`dart:developer`), with resilient lazy connections, hot-restart recovery, stable cursor pagination, security guardrails, and zero stdout pollution.

**Architecture:**
1. **Core Service Extension Layer (`packages/interceptly`):**
   - In debug mode, registers standard `ext.interceptly.*` service protocol extensions using Dart SDK's built-in `dart:developer`.
   - **Idempotent registration**: Handlers are registered once (`_isRegistered` guard). Multiple calls update the active engine instance rather than re-registering (preventing hot reload crashes).
   - **Typed Error Responses**: Throws `ServiceExtensionException(code, message)` mapped to:
     - `ServiceExtensionResponse.invalidParams` for missing/malformed arguments.
     - `ServiceExtensionResponse.extensionError` for execution or disabled state errors.
   - **Stable Cursor Pagination**: Monotonically increasing sequence numbers allow `since_id` cursor pagination on `list_requests` without being disrupted by FIFO buffer drops.
   - **Pure handler separation**: Handler functions are pure Dart functions (`handleXxx(engine, params) -> Map<String, dynamic>`), allowing 100% unit testability without mock VM services.
   - **Versioned API contract**: Exposes `extensionApiVersion: 1` in `ping` response.
2. **Standalone MCP CLI Package (`packages/interceptly_mcp`):**
   - A pure Dart CLI communicating with AI assistants over `stdio` using official `dart_mcp: ^0.5.2` (Dart project authors).
   - **SDK floor**: `sdk: '>=3.7.0 <4.0.0'` (required by `dart_mcp: ^0.5.2`). Compatible with Flutter >= 3.29.
   - **Exact dependencies**: `dart_mcp: ^0.5.2`, `vm_service: ^15.4.0`, `dtd: ^4.0.0`, `args: ^2.7.0`, `path: ^1.9.1`. Measure of success: `dart pub get` and `melos bootstrap` pass cleanly.
   - **Watertight Stdout Protection**:
     - `main()` runs inside `runZonedGuarded` with a custom `ZoneSpecification(print: ...)` intercepting ALL `print()` calls (including third-party packages) and redirecting to `stderr`.
     - Lint rule `avoid_print` enabled in `analysis_options.yaml`.
3. **Resilient Discovery & Security Guardrails:**
   - Priority 1: `--uri <uri>` (CLI argument).
   - Priority 2: `INTERCEPTLY_VM_SERVICE_URI` (custom environment variable).
   - Priority 3: DTD (Dart Tooling Daemon) if `--dtd-uri` or `DTD_URI` is provided, calling `dtd.getVmServices()` from `package:dtd`.
   - **Security restriction**: `connect_app(uri)` strictly validates that host is a loopback address (`127.0.0.1`, `localhost`, `::1`). External hosts are rejected.
   - **Mutation Opt-in**: `--allow-mutation` flag required for `set_network_simulation` and `clear_traffic`; otherwise returns an error explaining mutation is locked.
   - **Lazy connection & retry**: Connects on demand per tool call; if disconnected, attempts reconnect once before failing gracefully.
   - **Hot-restart isolate recovery**: When an isolate dies or an RPC fails with isolate error, queries `getVM()` to find the new isolate advertising `ext.interceptly.ping`.
   - **Disambiguation for multiple apps**: If multiple apps/isolates are found, returns a candidate list error rather than guessing.
4. **Token-Budgeting & Continuation:**
   - `list_requests` unifies listing, filtering (`all`, `failed`, `2xx`, `3xx`, `4xx`, `5xx`), searching, and cursor pagination (`since_id`, `limit`).
   - `get_request_detail` provides targeted extraction (`part: all | request_body | response_body | request_headers | response_headers`) with character budgeting (`max_chars`, default 4000) and `offset` for continuation of truncated bodies.

**Tech Stack:** Dart SDK >= 3.7.0, Flutter >= 3.29.0, `dart_mcp: ^0.5.2`, `vm_service: ^15.4.0`, `dtd: ^4.0.0`, `args: ^2.7.0`, `test`, `melos`.

**Spec:** Dart VM Service Protocol Extension + Stdio MCP Server Architecture.

## Global Constraints

- `packages/interceptly` must NOT depend on any MCP server or HTTP server package. It must strictly use `dart:developer` and `dart:convert`.
- Service extensions must only register in debug mode (`kDebugMode`) or when explicitly enabled; in release mode, they must be completely inert.
- `packages/interceptly_mcp` must be a pure Dart package with `sdk: '>=3.7.0 <4.0.0'`.
- All logging inside `packages/interceptly_mcp` must go to `stderr`. NEVER call `print()` or write unformatted strings to `stdout`.
- All code must pass `melos run check` (0 analyze errors, clean formatting, 100% passing core tests).

## Review Focus

1. **Stdout Pollution:** Absolutely zero non-JSON-RPC text on `stdout` under any circumstances (enforced via `ZoneSpecification(print: ...)` redirection to `stderr`).
2. **Hot Restart / Isolate Reconnect:** After a Flutter hot-restart (which destroys the isolate), the next MCP tool call must locate the newly created isolate without requiring a CLI restart.
3. **Loopback Enforced:** `connect_app` rejects non-loopback URIs with an explicit security exception.
4. **Mutation Protection:** Calling `set_network_simulation` or `clear_traffic` without `--allow-mutation` fails with permission error.
5. **Payload Continuation & Truncation:** Large responses can be read chunk-by-chunk using `get_request_detail(part: ..., offset: ..., max_chars: ...)` with metadata indicating total and remaining characters.

---

### Task 1: Core Service Extension Handlers in `packages/interceptly`

**Files:**
- Create: `packages/interceptly/lib/src/service_extension/interceptly_service_extensions.dart`
- Modify: `packages/interceptly/lib/src/core/interceptly_controller.dart`
- Test: `packages/interceptly/test/service_extension/interceptly_service_extensions_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class ServiceExtensionException implements Exception {
    final int errorCode; // ServiceExtensionResponse.invalidParams or extensionError
    final String message;
    ServiceExtensionException(this.errorCode, this.message);
  }

  class InterceptlyServiceExtensions {
    static const int extensionApiVersion = 1;
    static void register(InterceptlyEngine engine);
    static void enable();
    static void disable();
    static bool get isRegistered;
    static bool get isEnabled;

    // Pure handlers decoupled from dart:developer for direct testing:
    static Map<String, dynamic> handlePing({
      required InterceptlyEngine? engine,
      required Map<String, String> parameters,
      bool isEnabled = true,
    });
    static Map<String, dynamic> handleListRequests({
      required InterceptlyEngine? engine,
      required Map<String, String> parameters,
      bool isEnabled = true,
    });
    static Future<Map<String, dynamic>> handleGetRequestDetail({
      required InterceptlyEngine? engine,
      required Map<String, String> parameters,
      bool isEnabled = true,
    });
    static Map<String, dynamic> handleSetNetworkSimulation({
      required InterceptlyEngine? engine,
      required Map<String, String> parameters,
      bool isEnabled = true,
    });
    static Future<Map<String, dynamic>> handleClearTraffic({
      required InterceptlyEngine? engine,
      required Map<String, String> parameters,
      bool isEnabled = true,
    });
    static Map<String, dynamic> handleExportCurl({
      required InterceptlyEngine? engine,
      required Map<String, String> parameters,
      bool isEnabled = true,
    });
  }
  ```

- [x] **Step 1: Write unit tests for pure extension handlers**

In `packages/interceptly/test/service_extension/interceptly_service_extensions_test.dart`:
- Test `handlePing` returns `extensionApiVersion: 1`, `entryCount`, and `simulation`.
- Test `handleListRequests`:
  - `status_filter: 'all'`, `'failed'`, `'2xx'`, `'4xx'`, `'5xx'`
  - `search`: filters URL and method
  - `since_id`: cursor pagination (returns only entries after `since_id`)
  - `limit`: number of entries returned
- Test `handleGetRequestDetail`:
  - `part: 'all' | 'request_body' | 'response_body' | 'request_headers' | 'response_headers'`
  - `max_chars` and `offset` for continuation
  - Metadata `isTruncated`, `totalChars`, `remainingChars`
- Test error handling:
  - Missing required parameter `id` in `handleGetRequestDetail` throws `ServiceExtensionException(ServiceExtensionResponse.invalidParams, ...)`.
  - Calling when `isEnabled == false` throws `ServiceExtensionException(ServiceExtensionResponse.extensionError, ...)`.
- Test idempotency: calling `register()` multiple times does not throw and preserves engine reference.

- [x] **Step 2: Run test to verify it fails**

Run: `flutter test packages/interceptly/test/service_extension/interceptly_service_extensions_test.dart`
Expected: FAIL (file not found).

- [x] **Step 3: Implement `InterceptlyServiceExtensions`**

In `packages/interceptly/lib/src/service_extension/interceptly_service_extensions.dart`:
- Implement pure handler functions returning structured maps or throwing `ServiceExtensionException`.
- Wrap handlers in `dart:developer.registerExtension`:
  ```dart
  developer.registerExtension(name, (method, params) async {
    try {
      final result = await handler(params);
      return developer.ServiceExtensionResponse.result(jsonEncode(result));
    } on ServiceExtensionException catch (e) {
      return developer.ServiceExtensionResponse.error(
        e.errorCode,
        jsonEncode({'error': e.errorCode, 'message': e.message}),
      );
    } catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        jsonEncode({'message': e.toString()}),
      );
    }
  });
  ```
- Wire into `Interceptly.init()` when `kDebugMode` is true.

- [x] **Step 4: Run test to verify it passes**

Run: `flutter test packages/interceptly/test/service_extension/interceptly_service_extensions_test.dart`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add packages/interceptly/lib/src/service_extension packages/interceptly/lib/src/core/interceptly_controller.dart packages/interceptly/test/service_extension
git commit -m "feat(interceptly): add idempotent VM service protocol extensions with cursor pagination"
```

---

### Task 2: Scaffold `packages/interceptly_mcp` Package & Verified Dependencies

**Files:**
- Create: `packages/interceptly_mcp/pubspec.yaml`
- Create: `packages/interceptly_mcp/analysis_options.yaml`
- Create: `packages/interceptly_mcp/README.md`
- Create: `packages/interceptly_mcp/lib/interceptly_mcp.dart`
- Create: `packages/interceptly_mcp/lib/src/version.dart`
- Create: `packages/interceptly_mcp/lib/src/logging.dart`
- Create: `packages/interceptly_mcp/test/scaffold_test.dart`

**Interfaces:**
- `const String packageVersion = '1.0.0';`
- `const int minCompatibleExtensionApiVersion = 1;`
- `const int maxCompatibleExtensionApiVersion = 1;`
- `void logStderr(String message);`

- [x] **Step 1: Create `pubspec.yaml` and `analysis_options.yaml`**

In `packages/interceptly_mcp/pubspec.yaml`:
```yaml
name: interceptly_mcp
description: "Model Context Protocol (MCP) server for Interceptly Flutter network inspector."
version: 1.0.0
homepage: https://github.com/Tuanpluss02/interceptly
repository: https://github.com/Tuanpluss02/interceptly

environment:
  sdk: '>=3.7.0 <4.0.0'

dependencies:
  dart_mcp: ^0.5.2
  vm_service: ^15.4.0
  dtd: ^4.0.0
  args: ^2.7.0
  path: ^1.9.1

dev_dependencies:
  test: ^1.25.0
  lints: ^4.0.0
```

In `packages/interceptly_mcp/analysis_options.yaml`:
Enable `avoid_print: true` to prevent any print statements in code.

- [x] **Step 2: Create entrypoint, version constants, and stderr logging utility**

Create `lib/interceptly_mcp.dart`, `lib/src/version.dart`, and `lib/src/logging.dart`.
Ensure `logStderr` writes directly to `stderr.writeln(...)`.

- [x] **Step 3: Run Melos bootstrap and verify scaffold test**

Write `packages/interceptly_mcp/test/scaffold_test.dart` verifying constants and SDK floor.
Run: `melos bootstrap` (Success gate: pub get passes across packages)
Run: `dart test packages/interceptly_mcp/test/scaffold_test.dart`
Expected: PASS.

- [x] **Step 4: Commit**

```bash
git add packages/interceptly_mcp melos.yaml
git commit -m "feat(mcp): scaffold packages/interceptly_mcp with verified dart_mcp and avoid_print lint"
```

---

### Task 3: Headless VM Service Spike & Manual Flutter Checklist

**Files:**
- Create: `packages/interceptly_mcp/test/spike/vm_service_real_spike_test.dart`
- Create: `packages/interceptly_mcp/test/spike/fixtures/target_spike_app.dart`

**Automated Spike Goal:**
1. Spawns headless Dart app with `--enable-vm-service=0`.
2. Connects via `vmServiceConnectUri`.
3. Calls custom `ext.*` extension and verifies response.
4. Verifies `vmService.getVM()` enumerates isolates.

**Manual Verification Checklist (Documented in test doc):**
1. Run example app: `cd packages/interceptly/example && flutter run`
2. Run MCP CLI: `dart run packages/interceptly_mcp/bin/interceptly_mcp.dart --uri <printed-uri>`
3. Call `list_requests` in chat $\rightarrow$ verify traffic appears.
4. Press `R` in flutter run console (Hot Restart).
5. Call `list_requests` again $\rightarrow$ verify CLI reconnects to new isolate without crashing.

- [x] **Step 1: Create target spike app fixture**

Create `test/spike/fixtures/target_spike_app.dart` which registers a test extension `ext.spike.test` and keeps running.

- [x] **Step 2: Implement and run the automated spike test**

Write `test/spike/vm_service_real_spike_test.dart`:
- Spawns process using `Process.start('dart', ['--enable-vm-service=0', ...])`.
- Captures output to parse `ws://127.0.0.1:.../ws`.
- Connects using `vmServiceConnectUri(uri)`.
- Invokes `ext.spike.test` via `vmService.callServiceExtension`.
- Verifies isolate list retrieval via `vmService.getVM()`.
- Kills process cleanly.
Run: `dart test packages/interceptly_mcp/test/spike/vm_service_real_spike_test.dart`
Expected: PASS.

- [x] **Step 3: Commit**

```bash
git add packages/interceptly_mcp/test/spike
git commit -m "test(mcp): add automated VM service spike test and manual Flutter verification checklist"
```

---

### Task 4: Resilient VM Service Client, Loopback Guard & DTD Integration

**Files:**
- Create: `packages/interceptly_mcp/lib/src/client/app_discovery.dart`
- Create: `packages/interceptly_mcp/lib/src/client/vm_service_client.dart`
- Test: `packages/interceptly_mcp/test/client/app_discovery_test.dart`
- Test: `packages/interceptly_mcp/test/client/vm_service_client_test.dart`

**Interfaces:**
```dart
class DiscoveredApp {
  final Uri uri;
  final String? name;
  final String isolateId;
}

class AppDiscovery {
  static Future<Uri?> resolveUri({
    Uri? explicitUri,
    Map<String, String>? environment,
    Uri? dtdUri,
  });

  static bool isLoopbackUri(Uri uri);
  static Future<List<DiscoveredApp>> findCandidates(VmService service);
}

class VmServiceClient {
  bool get isConnected;
  int? get remoteExtensionApiVersion;
  String? get activeIsolateId;
  Uri? get connectedUri;

  Future<void> connect(Uri wsUri);
  Future<void> disconnect();
  Future<void> ensureConnected();
  Future<Map<String, dynamic>> invoke(String method, [Map<String, String>? params]);
}
```

- [ ] **Step 1: Write unit tests for discovery cascade, loopback validation, and resilient client**

In `app_discovery_test.dart` and `vm_service_client_test.dart`:
- Test discovery priority: `--uri` > `INTERCEPTLY_VM_SERVICE_URI` > DTD.
- Test loopback validation: `AppDiscovery.isLoopbackUri` accepts `127.0.0.1`, `localhost`, `::1`; rejects `192.168.1.1` or `malicious.site`.
- Test lazy connection: calling `invoke()` before `connect()` triggers `ensureConnected()`.
- Test isolate recovery: when extension call throws isolate error, client re-queries `getVM()` to find the new isolate and retries once.
- Test multiple apps: if multiple isolates or services register `ext.interceptly.ping`, throws `MultipleAppsException` containing candidate list.
- Test version range check: valid when `minCompatibleExtensionApiVersion <= remote <= maxCompatibleExtensionApiVersion`.
- Test error mapping: `RPCError` from VM service correctly bubbles for MCP error response.

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test packages/interceptly_mcp/test/client/vm_service_client_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `AppDiscovery` and `VmServiceClient`**

Implement connection handling, loopback validation, isolate cache invalidation, DTD lookup via `dtd.getVmServices()`, and retry logic. Ensure all diagnostic logs use `logStderr`.

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test packages/interceptly_mcp/test/client/app_discovery_test.dart packages/interceptly_mcp/test/client/vm_service_client_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly_mcp/lib/src/client packages/interceptly_mcp/test/client
git commit -m "feat(mcp): implement resilient VM service client with loopback guard and DTD integration"
```

---

### Task 5: MCP Server & Tool Definitions with Mutation Flag (using `dart_mcp`)

**Files:**
- Create: `packages/interceptly_mcp/lib/src/server/interceptly_mcp_server.dart`
- Create: `packages/interceptly_mcp/lib/src/tools/traffic_tools.dart`
- Create: `packages/interceptly_mcp/lib/src/tools/simulation_tools.dart`
- Create: `packages/interceptly_mcp/lib/src/tools/export_tools.dart`
- Test: `packages/interceptly_mcp/test/server/interceptly_mcp_server_test.dart`

**Interfaces:**
```dart
class InterceptlyMcpServer extends MCPServer with ToolsSupport, PromptsSupport {
  InterceptlyMcpServer({
    required VmServiceClient client,
    bool allowMutation = false,
    String? instructions,
  });
}
```
- Tools registered:
  - `ping`: Reports connection status, app name, entry count, and version skew.
  - `list_requests`: Filterable list (`all`, `failed`, `2xx`, `3xx`, `4xx`, `5xx`), search query, `since_id`, `limit`.
  - `get_request_detail`: Targeted inspection with `part: all | request_body | response_body | request_headers | response_headers`, `max_chars`, `offset`.
  - `set_network_simulation`: Protected by `allowMutation`.
  - `clear_traffic`: Protected by `allowMutation`.
  - `export_curl`: Replayable cURL string.
  - `connect_app`: Explicitly connects to a loopback VM Service URI when multiple candidates are detected.

- [ ] **Step 1: Write unit tests for MCP tool registrations and mutation security**

In `packages/interceptly_mcp/test/server/interceptly_mcp_server_test.dart` using a stub `VmServiceClient`:
- Test `ping` output with connected and disconnected states.
- Test `list_requests` with `since_id` cursor pagination and `status_filter`.
- Test `get_request_detail` with `part`, `offset`, and `max_chars`.
- Test mutation guard: calling `set_network_simulation` or `clear_traffic` when `allowMutation == false` returns `CallToolResult(isError: true)`.
- Test `connect_app` validates loopback host and rejects remote IPs.

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test packages/interceptly_mcp/test/server/interceptly_mcp_server_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `InterceptlyMcpServer` and tool definitions**

Subclass `MCPServer` with `ToolsSupport` and `PromptsSupport` from `package:dart_mcp/server.dart`. Register all tools with input schemas and error handling.

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test packages/interceptly_mcp/test/server/interceptly_mcp_server_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly_mcp/lib/src/server packages/interceptly_mcp/lib/src/tools packages/interceptly_mcp/test/server
git commit -m "feat(mcp): implement MCP server with mutation guard and cursor pagination"
```

---

### Task 6: Standalone CLI Executable (`bin/interceptly_mcp.dart`) with `runZonedGuarded`

**Files:**
- Create: `packages/interceptly_mcp/bin/interceptly_mcp.dart`
- Test: `packages/interceptly_mcp/test/cli/cli_test.dart`

**Interfaces:**
- Executable: `bin/interceptly_mcp.dart` supporting:
  - `--uri <ws://...>`: Explicit VM service URI override
  - `--dtd-uri <ws://...>`: Explicit DTD URI override
  - `--allow-mutation`: Enable mutation tools (`set_network_simulation`, `clear_traffic`)
  - `--help`, `-h`: Show usage instructions
  - `--version`: Show package version

- [ ] **Step 1: Write test for CLI argument parsing and Zone redirection**

Test parsing flags `--uri`, `--dtd-uri`, `--allow-mutation`, `--version`, and `--help`. Test that calls to `print()` inside the zone are routed to `stderr`.

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test packages/interceptly_mcp/test/cli/cli_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `bin/interceptly_mcp.dart`**

Wrap `main()` in `runZonedGuarded` with `ZoneSpecification(print: (self, parent, zone, line) => stderr.writeln(line))`. Parse arguments with `package:args`. Connect `stdioChannel(input: stdin, output: stdout)` to `InterceptlyMcpServer`. Handle SIGINT and SIGTERM gracefully.

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test packages/interceptly_mcp/test/cli/cli_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly_mcp/bin packages/interceptly_mcp/test/cli
git commit -m "feat(mcp): implement CLI binary with runZonedGuarded print redirection to stderr"
```

---

### Task 7: End-to-End Test with Real App & Melos Quality Gate

**Files:**
- Create: `packages/interceptly_mcp/test/e2e/e2e_real_app_test.dart`
- Modify: `packages/interceptly_mcp/README.md`
- Modify: `docs/development-guide/01-architecture.md`

- [ ] **Step 1: Write real End-to-End integration test**

In `packages/interceptly_mcp/test/e2e/e2e_real_app_test.dart`:
- Start a test app process running `InterceptlyEngine` with `InterceptlyServiceExtensions.register(engine)` and `--enable-vm-service=0`.
- Capture its VM Service WebSocket URI.
- Instantiate `InterceptlyMcpServer` connected to that URI with `--allow-mutation`.
- Simulate HTTP network calls into the engine.
- Call MCP tools via JSON-RPC:
  - `ping` -> verify version 1 and entry count
  - `list_requests(since_id: ...)` -> verify cursor pagination
  - `get_request_detail(id: ..., max_chars: 100)` -> verify truncated body and metadata
  - `set_network_simulation(profile: 'slow3g')` -> verify simulation state updated
- Verify that `stdout` contained ONLY valid JSON-RPC lines.
- Terminate test app process cleanly.

- [ ] **Step 2: Run E2E test to verify it passes**

Run: `dart test packages/interceptly_mcp/test/e2e/e2e_real_app_test.dart`
Expected: PASS.

- [ ] **Step 3: Run workspace pre-commit quality gate**

Run: `melos run check`
Verify:
1. `melos run format:check` -> 0 changes needed
2. `melos run analyze` -> 0 issues across all packages
3. `melos run test:core` -> 100% tests passing

- [ ] **Step 4: Document setup, security, and manual checklist**

Update `packages/interceptly_mcp/README.md` and `docs/development-guide/01-architecture.md` with:
- Installation: `dart pub global activate interceptly_mcp`
- Configuration for Cursor (`mcp.json`) and Claude Desktop
- Manual verification steps for Hot Restart in Flutter apps
- Security note on loopback restriction and `--allow-mutation`.

- [ ] **Step 5: Commit**

```bash
git add packages/interceptly_mcp/test/e2e packages/interceptly_mcp/README.md docs/
git commit -m "test(mcp): add real app end-to-end test and complete quality gate"
```
