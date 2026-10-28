# Contributing to Interceptly

Thank you for your interest in contributing to **Interceptly**! Interceptly is a client-agnostic network and realtime traffic inspector for Flutter.

This guide explains our monorepo structure, development workflow, commit conventions, and release automation.

---

## 1. Monorepo Architecture

Interceptly is structured as a monorepo managed with [Melos](https://melos.invertase.dev/):

```
.
├── packages/
│   ├── interceptly/              # Core inspector engine, background isolate, UI overlay
│   │   └── example/              # Interactive Flutter showcase app (REST, WebSocket, simulated chat)
│   ├── interceptly_dio/          # Dio interceptor adapter
│   ├── interceptly_http/         # package:http Client wrapper adapter
│   ├── interceptly_chopper/      # Chopper interceptor adapter
│   └── interceptly_web_socket/   # WebSocketChannel adapter
├── pubspec.yaml                  # Workspace config (workspace:, melos:) & scripts
└── .github/workflows/            # CI/CD pipelines
```

---

## 2. Getting Started

### Prerequisites

- **Flutter SDK**: `>= 3.24.0` (matching `.fvmrc`: `3.41.4`)
- **Dart SDK**: `>= 3.5.0 < 4.0.0`
- **Melos**: Version 6.x or newer

### Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/Tuanpluss02/interceptly.git
   cd interceptly
   ```

2. **Install Melos** (if not already installed):
   ```bash
   dart pub global activate melos 8.10.0
   ```

3. **Bootstrap the workspace**:
   ```bash
   melos bootstrap
   ```
   This resolves all dependencies and links monorepo packages together.

---

## 3. Git Workflow & Branching Strategy

We follow **GitHub Flow**:

1. **Protected Main Branch**: The `main` branch always represents production-ready code. Direct pushes are disabled.
2. **Feature Branches**: Create a descriptive branch from `main`:
   - `feat/<feature-name>`: New features or capabilities.
   - `fix/<bug-name>`: Bug fixes.
   - `refactor/<scope>`: Code refactoring without behavioral changes.
   - `docs/<topic>`: Documentation and guide updates.
   - `chore/<task>`: Dependency updates, CI/CD, or maintenance.

### Conventional Commits & PR Titles

We enforce [Conventional Commits](https://www.conventionalcommits.org/) on all Pull Request titles. Melos uses PR titles and commit history to automatically generate `CHANGELOG.md` and bump semantic versions.

**Format:**
```
<type>(<scope>): <short description in English>
```

- **Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`
- **Scopes**:
  - `interceptly`: Core engine, UI overlay, or session management.
  - `dio`, `http`, `chopper`, `web_socket`: Respective network adapters.
  - `example`: Example Flutter application.
  - `ci`: GitHub Actions or Melos setup.
  - `deps`: Dependency updates.
- **Breaking Changes**: Append a `!` after type/scope (e.g. `feat(interceptly)!: redesign init API`) or include `BREAKING CHANGE:` in the commit footer.

**Examples:**
- `feat(dio): add automatic request cancellation tracking`
- `fix(interceptly): resolve memory leak when clearing sessions`
- `docs(web_socket): add live streaming tutorial`

---

## 4. Development Commands (Melos Scripts)

Before submitting a Pull Request, use these commands to ensure your code meets our standards:

| Command | Purpose |
| :--- | :--- |
| `melos run check` | **Recommended pre-push check**: Runs format check, static analysis, and core tests. |
| `melos run format` | Automatically formats all Dart code across the repository. |
| `melos run format:check` | Verifies that all files conform to `dart format` without modifying them. |
| `melos run analyze` | Runs `dart analyze` across all 5 packages. Must pass with **0 issues**. |
| `melos run test` | Runs all 840+ unit, widget, and stress tests. |
| `melos run test:core` | Runs fast core unit and widget tests (excluding long stress tests). |
| `melos run test:stress` | Runs stress, performance, and memory virtualization tests. |
| `melos run coverage` | Runs tests and generates LCOV code coverage reports in `packages/*/coverage/`. |
| `melos run pana` | Runs the package health score audit for pub.dev (aiming for **160/160 points**). |
| `melos run clean` | Cleans build artifacts across all packages. |

---

## 5. Continuous Integration (CI)

Every Pull Request targeting `main` automatically triggers:

1. **PR Title Check (`semantic-pr.yml`)**: Verifies Conventional Commits compliance.
2. **Lint & Format (`ci.yml`)**: Validates `dart format` and `dart analyze`.
3. **Tests & Coverage (`ci.yml`)**: Runs all test suites and uploads code coverage artifacts.
4. **Package Health & Example (`ci.yml`)**: Runs `pana` score verification and builds the example app.

All status checks must pass before a PR can be merged.

---

## 6. Continuous Delivery (CD) & Publishing Guide (Maintainers)

Interceptly uses **Pub.dev OIDC Authentication** to publish packages without storing long-lived API tokens.

### One-Time Pub.dev OIDC Setup

For each package (`interceptly`, `interceptly_dio`, `interceptly_http`, `interceptly_chopper`, `interceptly_web_socket`):

1. Go to the package admin page on pub.dev:  
   `https://pub.dev/packages/<package_name>/admin`
2. Scroll to the **Automated publishing** section.
3. Check **Publish using GitHub Actions**.
4. Enter the GitHub repository: `Tuanpluss02/interceptly`.
5. Save changes.

### Triggering a Release

Releases are managed via GitHub Actions:

1. Navigate to **Actions** → **Release & Publish**.
2. Click **Run workflow**:
   - Set `dry_run = true` (default) to preview version increments and changelog diffs in the Actions log.
   - Set `dry_run = false` to perform the actual release.
3. The workflow will:
   - Run quality checks (`melos run check`).
   - Bump package versions and update `CHANGELOG.md` via `melos version`.
   - Commit and push git tags (`<package>-v<version>`).
   - Authenticate via OIDC and publish modified packages to pub.dev (`melos publish`).
   - Create GitHub Releases with auto-generated release notes.
