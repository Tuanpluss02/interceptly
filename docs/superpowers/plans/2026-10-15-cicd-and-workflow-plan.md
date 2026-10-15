# Interceptly Monorepo Workflow & CI/CD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish an open-source grade Git workflow and complete CI/CD automation for the Interceptly Flutter monorepo (lint, format, tests with coverage, pana pub score check, example verification, and automated Melos versioning/publishing to pub.dev via OIDC).

**Architecture:** GitHub Flow with Conventional Commits, Melos-driven monorepo scripts, GitHub Actions CI pipeline (`ci.yml` + `semantic-pr.yml`), and automated Pub.dev OIDC Release workflow (`release.yml`).

**Tech Stack:** GitHub Actions, Melos 6.x, Flutter SDK 3.41.x (>=3.24.0), Dart SDK >=3.5.0, pana, lcov, Pub.dev OIDC.

**Spec:** `docs/superpowers/specs/2026-10-15-cicd-and-workflow-design.md`

## Global Constraints

- Flutter SDK constraint: `>=3.24.0` (matching `.fvmrc`: `3.41.4`).
- Dart SDK constraint: `>=3.5.0 <4.0.0`.
- All 5 packages (`interceptly`, `interceptly_dio`, `interceptly_http`, `interceptly_chopper`, `interceptly_web_socket`) must pass `dart analyze` with 0 warnings/errors.
- All test suites (840+ tests) must pass 100%.
- Pub.dev automated publishing must use **OIDC** (`id-token: write` permission) without long-lived secret tokens.
- Git tags format: `{{packageName}}-v{{newVersion}}`.

## Review Focus

1. **Unformatted code in repository breaking CI**: 64 files currently deviate from `dart format`; format check must fail if not resolved before CI push.
2. **Pub score penalty on missing examples/topics**: Each package must have valid pub metadata to ensure highest possible score on pana check (up to 160 points).
3. **Melos versioning tag collisions**: Versioning must respect monorepo package isolation and tag prefixing `{{packageName}}-v{{newVersion}}`.
4. **OIDC token permission mismatch**: `release.yml` must explicitly declare `id-token: write` and `contents: write` or pub.dev token exchange fails.
5. **Fast-fail vs complete test reporting**: CI should separate lint/format, test, and pana into distinct jobs so failures are pinpointed immediately.

---

### Task 1: Standardize Code Formatting and Update Melos Monorepo Scripts

**Files:**
- Modify: `melos.yaml`
- Modify: (64 existing Dart files across packages and example)

**Interfaces:**
- Produces: `melos run format`, `melos run format:check`, `melos run check`, `melos run pana`

- [ ] **Step 1: Check formatting failures before fix**
Run: `dart format --output=none --set-exit-if-changed .`
Expected: Non-zero exit code (exit 1, 64 files changed).

- [ ] **Step 2: Apply dart format across monorepo**
Run: `dart format .`
Expected: All 221 files formatted, 0 remaining formatting violations.

- [ ] **Step 3: Update `melos.yaml` with versioning, publishing, and quality scripts**
Update `melos.yaml` to include:
```yaml
name: interceptly_monorepo
packages:
  - packages/*

command:
  version:
    message: 'chore(release): publish packages [skip ci]'
    linkToCommits: true
    workspaceChangelog: false
    branch: main
  publish:
    branch: main

scripts:
  analyze:
    exec: dart analyze .
    description: Run analyzer in all packages.

  format:
    exec: dart format .
    description: Format Dart files across all packages.

  format:check:
    exec: dart format --output=none --set-exit-if-changed .
    description: Verify that code is formatted across all packages.

  test:
    exec: flutter test
    concurrency: 1
    description: Run tests in all packages.

  test:core:
    exec: flutter test --exclude-tags=stress,perf
    description: Run core test suites excluding stress and perf tests.

  test:stress:
    exec: flutter test --tags=stress
    packageFilters:
      dirExists: test/stress
    description: Run stress test suites.

  coverage:
    exec: flutter test --coverage
    description: Run test suites and generate coverage reports.

  pana:
    exec: pana --no-warning --exit-code-threshold 1
    description: Analyze package pub health score.

  check:
    run: melos run format:check && melos run analyze && melos run test:core
    description: Run fast local pre-commit check (format, analyze, core tests).

  clean:
    exec: flutter clean
    description: Clean build artifacts in all packages.
```

- [ ] **Step 4: Verify format check and check command pass**
Run: `melos run format:check && melos run analyze`
Expected: SUCCESS for both scripts.

- [ ] **Step 5: Commit formatting and melos.yaml updates**
```bash
git add melos.yaml packages/
git commit -m "chore: format codebase and update melos scripts for CI/CD"
```

---

### Task 2: Implement Pull Request Title Linter Workflow

**Files:**
- Create: `.github/workflows/semantic-pr.yml`

**Interfaces:**
- Consumes: GitHub pull request title and events (`opened`, `edited`, `synchronize`, `reopened`)
- Produces: GitHub status check ensuring Conventional Commits

- [ ] **Step 1: Create `.github/workflows/semantic-pr.yml`**
Create workflow using `amannn/action-semantic-pull-request@v5`:
```yaml
name: "Lint PR Title"

on:
  pull_request_target:
    types:
      - opened
      - edited
      - synchronize
      - reopened

jobs:
  main:
    name: Validate PR Title
    runs-on: ubuntu-latest
    permissions:
      pull-requests: read
    steps:
      - uses: amannn/action-semantic-pull-request@v5
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          types: |
            feat
            fix
            docs
            style
            refactor
            perf
            test
            build
            ci
            chore
            revert
          scopes: |
            interceptly
            dio
            http
            chopper
            web_socket
            example
            deps
            release
          requireScope: false
```

- [ ] **Step 2: Verify YAML syntax and permissions**
Validate YAML file structure and action configurations.

- [ ] **Step 3: Commit semantic PR workflow**
```bash
git add .github/workflows/semantic-pr.yml
git commit -m "ci: add PR title linter workflow for conventional commits"
```

---

### Task 3: Implement Continuous Integration (CI) Workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: Code changes pushed to `main` or in PR targeting `main`
- Produces: Build/test/lint status checks and coverage report artifact

- [ ] **Step 1: Create `.github/workflows/ci.yml`**
Create multi-job CI workflow with:
- Job 1: `lint-and-format`:
  - `subosito/flutter-action@v2` with `channel: 'stable'`, `cache: true`
  - Activate Melos (`dart pub global activate melos`)
  - Run `melos bootstrap`
  - Run `melos run format:check`
  - Run `melos run analyze`
- Job 2: `test`:
  - Checkout and setup Flutter
  - Activate Melos and bootstrap
  - Run `melos run test`
  - Upload test coverage report artifact (`packages/*/coverage/lcov.info`)
- Job 3: `pana-and-example`:
  - Activate `pana` (`dart pub global activate pana`)
  - Run pana dry analysis on packages
  - Verify example app (`cd packages/interceptly/example && flutter analyze && flutter test`)

- [ ] **Step 2: Verify YAML syntax and structure**
Ensure proper indentation, job dependencies (`needs: [lint-and-format]`), and environment variables.

- [ ] **Step 3: Commit CI workflow**
```bash
git add .github/workflows/ci.yml
git commit -m "ci: add full continuous integration workflow"
```

---

### Task 4: Implement Continuous Delivery (CD) & Pub.dev Release Workflow

**Files:**
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `workflow_dispatch` with inputs `dry_run` (boolean) and `prerelease` (boolean)
- Produces: Git commits, release tags, GitHub Releases, and packages published to pub.dev via OIDC

- [ ] **Step 1: Create `.github/workflows/release.yml`**
Define workflow with:
- `permissions`:
  - `id-token: write`
  - `contents: write`
  - `pull-requests: read`
- Inputs:
  - `dry_run` (boolean, default: true)
  - `prerelease` (boolean, default: false)
- Steps:
  1. Checkout with `fetch-depth: 0`
  2. Setup Flutter and Dart
  3. Git config (`git config user.name "github-actions[bot]"` & email)
  4. Activate Melos and bootstrap
  5. Run pre-release checks (`melos run check`)
  6. Execute `melos version`:
     - If dry_run: `melos version --yes --no-git-tag-version` and display diff
     - If not dry_run: `melos version --yes` and push commits & tags
  7. Execute `melos publish`:
     - If dry_run: `melos publish --dry-run`
     - If not dry_run: `melos publish --yes --no-dry-run` (OIDC)
  8. Create GitHub Releases for newly generated tags

- [ ] **Step 2: Verify YAML permissions and OIDC security alignment**
Verify `id-token: write` is present at the job level.

- [ ] **Step 3: Commit release workflow**
```bash
git add .github/workflows/release.yml
git commit -m "ci: add automated release and pub.dev OIDC publishing workflow"
```

---

### Task 5: Add Community Collaboration Templates and Guidelines

**Files:**
- Create: `.github/PULL_REQUEST_TEMPLATE.md`
- Create: `.github/ISSUE_TEMPLATE/bug_report.yml`
- Create: `.github/ISSUE_TEMPLATE/feature_request.yml`
- Create: `CONTRIBUTING.md`

**Interfaces:**
- Consumes: Developer contributions, bug reports, and pull requests
- Produces: Standardized PR descriptions, structured issue reports, and onboarding docs

- [ ] **Step 1: Create `.github/PULL_REQUEST_TEMPLATE.md`**
Include summary, type of change, related issue, and checklist (tests, format, docs).

- [ ] **Step 2: Create GitHub Issue Templates**
Create `bug_report.yml` and `feature_request.yml` with structured dropdowns and code blocks for logs.

- [ ] **Step 3: Create `CONTRIBUTING.md`**
Document:
- Monorepo structure and prerequisites (Flutter, FVM, Melos)
- Conventional Commits specification with examples
- Development commands (`melos run check`, `melos run format`, `melos run test`)
- Pub.dev OIDC setup guide for project maintainers

- [ ] **Step 4: Commit templates and guidelines**
```bash
git add .github/ CONTRIBUTING.md
git commit -m "docs: add PR template, issue templates, and contributing guide"
```

---

### Task 6: End-to-End Local Verification

**Files:**
- Verify: Entire monorepo state

- [ ] **Step 1: Run format check across monorepo**
Run: `melos run format:check`
Expected: Exit code 0 (SUCCESS).

- [ ] **Step 2: Run static analysis across monorepo**
Run: `melos run analyze`
Expected: Exit code 0 (SUCCESS, 0 issues found).

- [ ] **Step 3: Run core tests across monorepo**
Run: `melos run test:core`
Expected: Exit code 0 (All tests passed).

- [ ] **Step 4: Verify example app health**
Run: `cd packages/interceptly/example && flutter analyze && flutter test`
Expected: 0 issues, all tests pass.

- [ ] **Step 5: Verify git status is clean**
Run: `git status`
Expected: Clean working tree, all changes committed on the appropriate branch.
