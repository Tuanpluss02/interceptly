# Interceptly Monorepo — Agent Guidelines

You are an AI assistant developing and maintaining the **Interceptly** codebase.
Interceptly is a client-agnostic network and realtime traffic inspector for Flutter applications.

---

## 1. Monorepo Architecture

This repository is managed with [Melos](https://melos.invertase.dev/). It is organized into 6 publishable packages and 1 example app:

- `packages/interceptly`: Core engine (`InterceptlyEngine`), UI overlay (`InterceptlyScope`), background isolate pipeline (`WriterIsolate`), hybrid RAM/disk storage (`BodyStore`, `RealtimeBodyStore`), and public singleton facade (`Interceptly`).
- `packages/interceptly_dio`: Adapter interceptor for `Dio`.
- `packages/interceptly_http`: Adapter client wrapper for `package:http`.
- `packages/interceptly_chopper`: Adapter interceptor for `Chopper`.
- `packages/interceptly_web_socket`: Adapter channel wrapper for `web_socket_channel` / raw WebSocket.
- `packages/interceptly_socket_io`: Adapter tracker for `socket_io_client`.
- `packages/interceptly/example`: Showcase and verification app.

---

## 2. Essential Melos Commands

Always use Melos commands across workspace packages:

- **Bootstrap**: `melos bootstrap` (links workspace dependencies and runs pub get)
- **Analyze**: `melos run analyze` (runs `dart analyze` across all packages)
- **Format check**: `melos run format:check` (verifies Dart formatting)
- **Apply format**: `melos run format` (auto-formats code with `dart format`)
- **Run core tests**: `melos run test:core` (runs fast non-stress tests across packages)
- **Pre-commit quality gate**: `melos run check` (runs format:check, analyze, and test:core)
- **Pub health check**: `melos run pana` (evaluates `interceptly` pub health score, aiming for 160/160)

---

## 3. Engineering & Architecture Rules

### Type-Safety & SPI
- The core package exposes `HttpTrafficCollector` and `RealtimeTrafficCollector` as the service provider interface (SPI) for adapters.
- Adapters must interact only through public collector APIs (`begin`, `startRequest`, `completeResponse`, `failRequest`, `shouldCapture`).
- Never use `dynamic` to bypass type checks or hide API divergence. Maintain strong typing across all packages.

### Lifecycle in Tests
- `Interceptly.instance` and `InterceptlyEngine.instance` are shared singletons.
- In unit/widget tests that interact with `Interceptly` or collectors, **always** call and `await Interceptly.resetForTesting()` in `setUp()` and `tearDown()` to prevent isolate race conditions and cross-test state leakage.

### SemVer & Inter-Package Dependencies
- If a new public API or parameter is added to `packages/interceptly`, bump its SemVer version appropriately.
- Satellite adapter packages must declare accurate dependency lower bounds (e.g., `interceptly: ^2.2.0` when requiring APIs introduced in 2.2.0).
- Never commit `pubspec_overrides.yaml` or local `path:` dependencies into published package pubspecs.

### Isolation & Performance
- All response body decoding, search indexing, and disk serialization MUST remain off the UI thread via `WriterIsolate` or dedicated isolate pipelines.
- Never add blocking work to the main Flutter isolate on the network hot path.

---

## 4. Development Workflow

- Always run `melos run check` before concluding any feature or bugfix to ensure 0 analyzer issues, 0 formatting errors, and 100% passing tests.

---

## 5. Technical Architecture Reference

For detailed architecture specifications, SPI contracts, code conventions, testing patterns, performance guardrails, and debugging checklists, refer directly to the development guide modules:

| # | Module | Scope |
|---|--------|-------|
| 01 | [`01-architecture.md`](docs/development-guide/01-architecture.md) | Monorepo structure, core vs adapter responsibilities |
| 02 | [`02-spi-contracts.md`](docs/development-guide/02-spi-contracts.md) | `HttpTrafficCollector`, `HttpCaptureScope`, `RealtimeTrafficCollector`, `RealtimeSessionScope` |
| 03 | [`03-core-internals.md`](docs/development-guide/03-core-internals.md) | `InterceptlyEngine`, `CapturePipeline`/`WriterIsolate`, hybrid storage, truncation |
| 04 | [`04-code-conventions.md`](docs/development-guide/04-code-conventions.md) | Type safety, adapter patterns, async/error handling, naming |
| 05 | [`05-quality-rules.md`](docs/development-guide/05-quality-rules.md) | `melos run check`, analyze, format, pana 160/160, test requirements |
| 06 | [`06-adapter-development.md`](docs/development-guide/06-adapter-development.md) | Step-by-step new adapter, checklist, SPI compliance |
| 07 | [`07-performance.md`](docs/development-guide/07-performance.md) | Hot-path rules, memory budgets, profiling hooks |
| 08 | [`08-debugging.md`](docs/development-guide/08-debugging.md) | Common pitfalls, debugging checklist, key files to read |
| 09 | [`09-versioning-ci.md`](docs/development-guide/09-versioning-ci.md) | SemVer policy, CI/CD workflow matrix |

This guide is the authoritative source for contributors and agents working on the Interceptly codebase.
