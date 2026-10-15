# Interceptly Monorepo Workflow & CI/CD Design Spec

- **Date:** 2026-10-15
- **Status:** Approved
- **Repository:** `Tuanpluss02/interceptly`
- **Scope:** Monorepo (`interceptly`, `interceptly_dio`, `interceptly_http`, `interceptly_chopper`, `interceptly_web_socket`, and `example`)

---

## 1. Mục tiêu (Objectives)

Thiết lập một quy trình phát triển chuyên nghiệp chuẩn mã nguồn mở (Open-source Standard) cho monorepo `interceptly`, bao gồm:
1. **Git & Collaboration Workflow**: GitHub Flow với Conventional Commits, branch protection, PR template và Issue templates.
2. **Local Developer Experience**: Cập nhật `melos.yaml` với các script chuẩn hóa (`check`, `format`, `analyze`, `test`, `pana`).
3. **Continuous Integration (CI)**: GitHub Actions tự động kiểm tra cú pháp, format, static analysis, 100% test suites (840+ tests), package health check (`pana` hướng tới điểm tối đa 160/160), và build verify example app.
4. **Continuous Delivery (CD)**: Tự động hóa tạo changelog, bump version theo Semantic Versioning bằng Melos, phát hành GitHub Releases, và xuất bản tự động lên [pub.dev](https://pub.dev) thông qua cơ chế **Pub.dev OIDC Authentication** (bảo mật không cần lưu secret token).

---

## 2. Kiến trúc tổng thể (Architecture Overview)

```
                            Developer Machine
                       (melos run check / format)
                                   │
                                   │ git push feature/xxx
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                             GitHub Repository                               │
│                                                                             │
│  Pull Request (Target: main)                                                │
│  ├── PR Title Linter (Conventional Commits: feat, fix, chore...)            │
│  └── CI Workflow (.github/workflows/ci.yml):                                │
│       ├── Job 1: Format & Static Analysis (dart format, melos analyze)       │
│       ├── Job 2: Test Suites & Coverage (melos test, lcov upload)           │
│       └── Job 3: Package Health & Example (pana 160 pts check, example app) │
│                                                                             │
│  Merge to main (All checks must PASS)                                       │
│                                                                             │
│  Release Workflow (.github/workflows/release.yml)                           │
│  └── Trigger: workflow_dispatch (dry_run: true/false)                       │
│       ├── 1. Run Pre-release Quality Gate (analyze & tests)                  │
│       ├── 2. melos version --yes (Bumps SemVer, updates CHANGELOG.md)        │
│       ├── 3. Git commit & push tags (e.g. interceptly-v2.1.1)               │
│       ├── 4. melos publish (Pub.dev OIDC Token Exchange)                    │
│       └── 5. GitHub Release Creation (with CHANGELOG release notes)         │
└─────────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
                         https://pub.dev/packages
```

---

## 3. Chi tiết thiết kế (Detailed Design)

### 3.1. Git Branching Strategy & Commit Standard

* **Nhánh chính (`main`)**:
  - Nhánh duy nhất phản ánh code production-ready.
  - Được bảo vệ bằng GitHub Branch Protection Rule: yêu cầu ít nhất 1 review approved, tất cả status checks của CI phải PASS, không cho phép direct push hoặc force push.
* **Quy ước đặt tên nhánh**:
  - `feat/<short-description>`: Tính năng mới.
  - `fix/<short-description>`: Vá lỗi.
  - `refactor/<short-description>`: Tái cấu trúc logic hoặc UI.
  - `docs/<short-description>`: Viết thêm hoặc sửa tài liệu.
  - `chore/<short-description>`: Nâng cấp dependencies, build tool, CI/CD.
* **Quy chuẩn Conventional Commits**:
  - Format: `<type>(<scope>): <subject>`
  - Types hợp lệ: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
  - Scopes chính: `interceptly`, `dio`, `http`, `chopper`, `web_socket`, `example`, `deps`, `release`.
  - Breaking changes: Thêm dấu `!` sau type/scope hoặc có dòng `BREAKING CHANGE:` ở footer.
* **Kiểm tra tự động PR Title**:
  - Sử dụng GitHub Action `amannn/action-semantic-pull-request` trong `.github/workflows/semantic-pr.yml`.
  - Kiểm tra tiêu đề PR ngay khi mở hoặc cập nhật.

### 3.2. Cấu hình Melos (`melos.yaml`)

Cập nhật `melos.yaml` ở thư mục gốc:
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

### 3.3. Pipeline CI: `.github/workflows/ci.yml`

* **Triggers**:
  ```yaml
  on:
    pull_request:
      branches: [main]
    push:
      branches: [main]
  ```
* **Jobs**:
  1. **`lint-and-format`**:
     - Runner: `ubuntu-latest`.
     - Setup Flutter: Sử dụng `subosito/flutter-action@v2` với version từ `.fvmrc` (hoặc `3.24.x` / stable) và cache enabled.
     - Bootstrap Melos.
     - Check format: `dart format --output=none --set-exit-if-changed .`.
     - Check analyzer: `melos run analyze`.
  2. **`test`**:
     - Chạy song song sau khi `lint-and-format` pass (hoặc chạy độc lập để tiết kiệm thời gian tổng).
     - Chạy `melos run test`.
     - Thu thập file coverage (`lcov.info`) và upload GitHub Artifact.
  3. **`pana-and-example`**:
     - Cài đặt `pana` via `dart pub global activate pana`.
     - Chạy pana check trên 5 packages để đảm bảo tuân thủ tiêu chí pub.dev 160 điểm.
     - Kiểm tra app `example`: chạy `flutter analyze` và `flutter test` trong thư mục `packages/interceptly/example`.

### 3.4. Pipeline CD: `.github/workflows/release.yml`

* **Triggers**:
  ```yaml
  on:
    workflow_dispatch:
      inputs:
        dry_run:
          description: 'Dry run (preview changes without publishing to pub.dev or pushing tags)'
          required: true
          type: boolean
          default: true
        prerelease:
          description: 'Publish as pre-release'
          required: false
          type: boolean
          default: false
  ```
* **Security & Permissions**:
  ```yaml
  permissions:
    id-token: write # Bắt buộc cho Pub.dev OIDC
    contents: write # Bắt buộc để push commit release & tag
    pull-requests: read
  ```
* **Quy trình các bước (Steps)**:
  1. **Checkout**: `actions/checkout@v4` với `fetch-depth: 0` (để Melos đọc toàn bộ git tag & commit history).
  2. **Setup Flutter & Dart SDK**: Khởi tạo môi trường.
  3. **Setup Git Config**: Cấu hình `git user.name: "github-actions[bot]"` và `git user.email: "github-actions[bot]@users.noreply.github.com"`.
  4. **Quality Gate**: Chạy `melos run check` để đảm bảo code hoàn toàn hợp lệ trước khi tiến hành release.
  5. **Melos Version**:
     - Nếu `dry_run == true`: Chạy `melos version --yes --no-git-tag-version` và hiển thị diff `git status` + CHANGELOG.
     - Nếu `dry_run == false`: Chạy `melos version --yes`, push commit & tags lên origin `main`.
  6. **Publish to Pub.dev**:
     - Nếu `dry_run == true`: Chạy `melos publish --dry-run`.
     - Nếu `dry_run == false`: Chạy `melos publish --yes --no-dry-run` (OIDC tự động cấp quyền dựa trên repo `Tuanpluss02/interceptly`).
  7. **Create GitHub Releases**: Tự động parse tag mới sinh ra và tạo GitHub Release tương ứng với nội dung lấy từ CHANGELOG.

### 3.5. Templates & Hướng dẫn đóng góp

1. **`.github/PULL_REQUEST_TEMPLATE.md`**:
   - Tóm tắt thay đổi (Summary).
   - Loại thay đổi (Bug fix, Feature, Breaking change, Refactor, Docs, Chore).
   - Danh sách kiểm tra chất lượng (Đã chạy test cục bộ, đã format code, đã kiểm tra example app).
2. **`.github/ISSUE_TEMPLATE/`**:
   - `bug_report.yml`: Thu thập môi trường (Flutter version, Device/OS, Adapter sử dụng, Steps to reproduce, Logs).
   - `feature_request.yml`: Mô tả tính năng và Use-case.
3. **`CONTRIBUTING.md`**:
   - Hướng dẫn clone, install FVM & Melos, chạy bootstrap.
   - Hướng dẫn các lệnh `melos run check`, `melos run format`.
   - Quy định Conventional Commits và quy trình mở PR.
4. **Hướng dẫn cấu hình Pub.dev OIDC (1 lần)**:
   - Truy cập `pub.dev` -> Trang quản lý package (ví dụ: `https://pub.dev/packages/interceptly/admin`).
   - Vào mục **Automated publishing**.
   - Bật **Publish using GitHub Actions**.
   - Điền Repository: `Tuanpluss02/interceptly`.
   - Làm tương tự cho 4 packages adapter còn lại.

---

## 4. Kế hoạch xác minh (Verification Strategy)

1. **Cục bộ (Local Verification)**:
   - Chạy `dart format .` để giải quyết triệt để 64 file chưa format.
   - Chạy `melos run format:check` -> Đảm bảo exit code 0.
   - Chạy `melos run check` -> Đảm bảo chuỗi kiểm tra hoàn tất thành công.
2. **GitHub Actions Syntax Verification**:
   - Dùng `actionlint` hoặc kiểm tra chặt chẽ cú pháp YAML của `.github/workflows/ci.yml`, `semantic-pr.yml`, `release.yml`.
3. **Chạy thử nghiệm (Dry-Run Release)**:
   - Kiểm tra lệnh `melos version --dry-run` hoặc mô phỏng tạo version tag trong môi trường local để đảm bảo regex tag và CHANGELOG sinh ra đúng chuẩn.
