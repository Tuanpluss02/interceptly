# 01 — Monorepo Architecture & Package Responsibilities

> **Scope:** Repository layout, package boundaries, core vs adapter separation.

---

## Repository Layout

```
packages/
├── interceptly/                    # CORE — single source of truth
│   ├── lib/
│   │   ├── adapter.dart            # SPI exports (HttpTrafficCollector, RealtimeTrafficCollector, etc.)
│   │   ├── interceptly.dart        # Public API exports
│   │   └── src/
│   │       ├── adapter/            # SPI implementations & contracts
│   │       │   ├── http_capture_scope.dart
│   │       │   ├── http_request_context.dart
│   │       │   ├── http_traffic_collector.dart
│   │       │   ├── realtime_session_scope.dart
│   │       │   └── realtime_traffic_collector.dart
│   │       ├── capture/            # Capture primitives (body_bytes, stream_capture, capture_guard)
│   │       ├── core/               # Public facade
│   │       │   └── interceptly_controller.dart   # Public singleton facade (Interceptly)
│   │       ├── engine/             # Headless coordinator, background pipelines & hybrid storage (@internal)
│   │       │   ├── interceptly_engine.dart       # Headless coordinator (@internal)
│   │       │   ├── capture_pipeline.dart         # WriterIsolate bridge
│   │       │   ├── writer_isolate.dart           # Background isolate logic
│   │       │   ├── body_store.dart               # RAM+disk hybrid storage
│   │       │   ├── realtime_body_store.dart      # WebSocket frame storage
│   │       │   ├── memory_index.dart             # In-memory index (RingBuffer + BoundedEventQueue)
│   │       │   ├── pending_tracker.dart          # In-flight request tracking
│   │       │   ├── realtime_store.dart           # WebSocket session registry
│   │       │   └── ...
│   │       ├── export/             # HAR/cURL/Postman exporters
│   │       ├── model/              # Data models (RawCapture, RequestRecord, BodyTruncation, etc.)
│   │       ├── share/              # System share / export integration
│   │       ├── simulation/         # Network simulation service & profile management
│   │       └── ui/                 # Inspector overlay, tabs, detail views
│   │           └── scope/          # UI Scope & presentation state (@internal)
│   └── test/                       # Unit, widget, stress, e2e tests
├── interceptly_dio/                # ADAPTER — Dio interceptor
├── interceptly_http/               # ADAPTER — http.Client wrapper
├── interceptly_chopper/            # ADAPTER — Chopper interceptor
├── interceptly_web_socket/         # ADAPTER — WebSocketChannel wrapper
├── interceptly_socket_io/          # ADAPTER — Socket.IO client tracker
├── interceptly_mcp/                # TOOL — Model Context Protocol (MCP) server for AI agents
└── interceptly/example/            # Showcase app (not published)
```

---

## Package Responsibilities

| Package | Role | Publishes to pub.dev |
|---------|------|---------------------|
| `interceptly` | Core engine: UI overlay (`InterceptlyScope`), background isolate pipeline, hybrid storage, headless data engine (`InterceptlyEngine`), public facade (`Interceptly`), network simulation, VM service extensions | ✅ |
| `interceptly_mcp` | Standalone pure Dart MCP server communicating with AI assistants over stdio and Flutter over VM Service | ✅ |
| `interceptly_dio` | `Dio` interceptor translating callbacks → SPI | ✅ |
| `interceptly_http` | `http.Client` wrapper (stream-teeing) translating → SPI | ✅ |
| `interceptly_chopper` | `Chopper` interceptor translating → SPI | ✅ |
| `interceptly_web_socket` | `WebSocketChannel` wrapper translating → SPI | ✅ |
| `interceptly_socket_io` | `socket_io_client` tracker translating callbacks → SPI | ✅ |
| `interceptly/example` | Interactive Flutter showcase (REST + WebSocket) | ❌ |

---

## Key Principle

> **Core owns all logic. Adapters are thin delegates** — they translate framework-specific callbacks into SPI calls and nothing else.

- No business logic in adapters
- No direct internal engine calls from adapters (interact strictly via Collector SPI)
- All capture, storage, simulation, truncation lives in core
- Adapters encapsulate framework client/interceptor and delegate lifecycle events to `HttpTrafficCollector` or `RealtimeTrafficCollector`

---

## Dependency Direction

```
Adapter packages  ──depends on──►  interceptly (core)
       │                                   │
       │                                   ▼
       │                            SPI interfaces
       │                            (HttpTrafficCollector, etc.)
       │                                   │
       └────── implements ─────────────────┘
```

Adapters declare `interceptly: ^X.Y.Z` matching the SPI version they implement against.

---

## Melos Workspace

- `melos.yaml` defines scripts: `bootstrap`, `analyze`, `format`, `test:core`, `check`, `pana`
- `packages: ['packages/*']` auto-includes all packages
- `pubspec_overrides.yaml` in each adapter points to local `../interceptly` during development