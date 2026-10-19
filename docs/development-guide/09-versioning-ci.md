# 09 — Version Policy & CI/CD

> **Scope:** SemVer rules for core vs adapters, CI/CD workflow matrix.

---

## 9.1 Semantic Versioning Policy

### Core (`interceptly`) = SPI Version

| Core Change | Core Version | Adapter Impact | Adapter Version |
|-------------|--------------|----------------|-----------------|
| New optional SPI param | Minor (2.2.0 → 2.3.0) | No change needed (default values) | No change |
| New required SPI param | Minor (2.2.0 → 2.3.0) | Adapters must update | Minor (^2.3.0 required) |
| SPI method removed/renamed | Major (2.x → 3.0.0) | Adapters must update | Major (3.0.0) |
| Internal refactor (no SPI change) | Patch (2.2.0 → 2.2.1) | No adapter change | No change |
| New adapter package | N/A | N/A | Initial 1.0.0 |

### Adapter Version Declaration

```yaml
# In adapter pubspec.yaml
dependencies:
  interceptly: ^2.2.0  # ^X.Y where X.Y = SPI version built against
```

**Rule:** Adapters declare `interceptly: ^X.Y.Z` where X.Y matches the SPI version they implement.

---

## 9.2 Modifying Core SPI (Breaking Changes Procedure)

If you change `HttpTrafficCollector`, `HttpCaptureScope`, `RealtimeTrafficCollector`, or `RealtimeSessionScope`:

1. **Bump core version** in `packages/interceptly/pubspec.yaml`
2. **Update ALL adapters** to match new signatures (same PR — they live in monorepo)
3. **Update `pubspec_overrides.yaml`** in adapters to point to local core during development
4. **Run `melos run check`** — all 5 packages must pass
5. **Document in CHANGELOG.md** under core package

### Example: Adding Required Param

```dart
// Core: Add required param to HttpTrafficCollector.completeResponse()
void completeResponse({
  ...
  required bool responseTruncatedAtStorage,  // NEW REQUIRED
});

// 1. Core: packages/interceptly/pubspec.yaml → version: 2.3.0
// 2. All adapters: update calls to include responseTruncatedAtStorage
// 3. Adapters: pubspec.yaml → interceptly: ^2.3.0
// 4. melos run check (all pass)
// 5. CHANGELOG.md: "feat(interceptly): add responseTruncatedAtStorage to completeResponse"
```

---

## 9.3 Release Workflow

### Trigger (Manual)

1. GitHub Actions → **Release & Publish** → **Run workflow**
2. `dry_run: true` (default) → Preview version bumps + changelog diffs
3. `dry_run: false` → Actual release

### Automated Steps

```yaml
# release.yml
- Run quality checks: melos run check
- Bump versions & changelog: melos version --yes
- Commit & push git tags: <package>-v<version>
- Publish via OIDC: melos publish --yes
- Create GitHub Releases with auto-generated notes
```

### Pub.dev OIDC Setup (One-Time Per Package)

1. Go to `https://pub.dev/packages/<package>/admin`
2. **Automated publishing** → Check "Publish using GitHub Actions"
3. Repository: `Tuanpluss02/interceptly`
4. Save

---

## 9.4 CI Pipeline Matrix

| Workflow | File | Trigger | Jobs |
|----------|------|---------|------|
| **PR Validation** | `ci.yml` | PR/push to main | `lint-and-format` → `test` → `pana-and-example` |
| **Release** | `release.yml` | Manual dispatch | `release` (quality → version → publish) |
| **PR Title** | `semantic-pr.yml` | PR opened | Validates Conventional Commits |

### Job Details

#### `ci.yml` — `lint-and-format` (ubuntu-latest)
```yaml
- checkout
- setup Flutter (stable)
- install Melos
- melos bootstrap
- melos run format:check
- melos run analyze
```

#### `ci.yml` — `test` (ubuntu-latest, needs lint-and-format)
```yaml
- checkout
- setup Flutter
- install Melos
- melos bootstrap
- melos run coverage
- upload lcov artifacts
```

#### `ci.yml` — `pana-and-example` (ubuntu-latest, needs lint-and-format)
```yaml
- checkout
- setup Flutter
- install Melos, pana, dartdoc
- melos bootstrap
- melos run pana          # 160/160 all packages
- cd packages/interceptly/example
- flutter analyze
- flutter test
```

#### `release.yml` — `release` (ubuntu-latest)
```yaml
- checkout (fetch-depth: 0 for tags)
- setup Dart (OIDC token)
- setup Flutter
- install Melos
- melos bootstrap
- melos run check         # Quality gate
- melos version           # Version bump + changelog
- git push --follow-tags
- melos publish (OIDC)    # Pub.dev
- gh release create       # GitHub Releases
```

---

## 9.5 Branch & Commit Conventions

### Branch Naming
```
feat/<feature-name>      # New features
fix/<bug-name>           # Bug fixes
refactor/<scope>         # Refactoring
docs/<topic>             # Documentation
chore/<task>             # Maintenance, deps, CI
```

### Conventional Commits (Enforced on PR Title)

```
<type>(<scope>): <short description>

# Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
# Scopes: interceptly, dio, http, chopper, web_socket, example, ci, deps
# Breaking: feat(interceptly)!: ... or BREAKING CHANGE: in footer
```

**Examples:**
```
feat(dio): add automatic request cancellation tracking
fix(interceptly): resolve memory leak when clearing sessions
docs(web_socket): add live streaming tutorial
chore(deps): upgrade dio to 5.11.1
```

---

## 9.6 Quality Gates Summary

| Gate | Command | Local | CI |
|------|---------|-------|----|
| Format | `melos run format:check` | ✅ | ✅ (lint-and-format) |
| Analysis | `melos run analyze` | ✅ | ✅ (lint-and-format) |
| Core Tests | `melos run test:core` | ✅ | ✅ (test) |
| Full Check | `melos run check` | ✅ | — |
| pana | `melos run pana` | ✅ | ✅ (pana-and-example) |
| Example App | `flutter analyze && flutter test` | ✅ | ✅ (pana-and-example) |

**Rule:** All gates must pass locally before pushing. CI is verification, not debugging.