# 05 — Quality Rules (Enforced by CI)

> **Scope:** `melos run check` gate, static analysis, formatting, pana, test requirements.

---

## 5.1 Mandatory Pre-Push Gate

```bash
melos run check
# Runs: format:check → analyze → test:core
# MUST pass with 0 issues before any PR
```

### What `check` Runs

```yaml
# melos.yaml
scripts:
  check:
    run: melos run format:check && melos run analyze && melos run test:core
```

---

## 5.2 Static Analysis — Zero Tolerance

```bash
melos run analyze  # Runs `dart analyze` across all 5 packages
```

**Requirement:** **0 errors, 0 warnings, 0 lints** across ALL packages.

### `analysis_options.yaml` (Root)

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  plugins:
    - custom_lint
  errors:
    invalid_annotation_target: ignore
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"

linter:
  rules:
    - always_declare_return_types
    - annotate_overrides
    - avoid_dynamic_called
    - avoid_empty_else
    - avoid_init_to_null
    - avoid_null_checks_in_equality_operators
    - avoid_positional_boolean_parameters
    - avoid_redundant_argument_values
    - avoid_return_types_on_setters
    - avoid_single_cascade_in_expression_statements
    - avoid_type_to_string
    - await_only_futures
    - camel_case_extensions
    - cancel_subscriptions
    - close_sinks
    - collection_methods_unrelated_type
    - combinators_ordering
    - comment_references
    - deprecated_consistency
    - do_not_use_environment
    - hash_and_equals
    - implementation_imports
    - join_return_with_assignment
    - literal_only_boolean_expressions
    - no_adjacent_strings_in_list
    - no_duplicate_case_values
    - no_leading_underscores_for_library_prefixes
    - no_leading_underscores_for_local_identifiers
    - no_runtimeType_toString
    - no_self_assignments
    - no_wildcard_variable_uses
    - nullable_type_in_async_future
    - prefer_adjacent_string_concatenation
    - prefer_collection_literals
    - prefer_conditional_assignment
    - prefer_const_constructors
    - prefer_const_constructors_in_immutables
    - prefer_const_declarations
    - prefer_const_literals_to_create_immutables
    - prefer_constructors_over_static_methods
    - prefer_contains
    - prefer_final_fields
    - prefer_final_locals
    - prefer_final_parameters
    - prefer_function_declarations_over_variables
    - prefer_generic_function_type_aliases
    - prefer_if_null_operators
    - prefer_inlining_local_variables
    - prefer_interpolation_to_compose_strings
    - prefer_is_empty
    - prefer_is_not_empty
    - prefer_iterable_whereType
    - prefer_mixin
    - prefer_null_aware_operators
    - prefer_relative_imports
    - prefer_single_quotes
    - prefer_spread_collections
    - prefer_typing_uninitialized_variables
    - recursive_getters
    - require_trailing_commas
    - sort_child_properties_last
    - sort_constructors_first
    - sort_unnamed_constructors_first
    - unawaited_futures
    - unnecessary_await_in_return
    - unnecessary_breaks
    - unnecessary_constructor_name
    - unnecessary_final
    - unnecessary_getters_setters
    - unnecessary_lambdas
    - unnecessary_null_aware_assignments
    - unnecessary_null_checks
    - unnecessary_nullable_for_final_variable_declarations
    - unnecessary_overrides
    - unnecessary_parenthesis
    - unnecessary_raw_strings
    - unnecessary_string_escapes
    - unnecessary_string_interpolations
    - unsafe_html
    - use_build_context_synchronously
    - use_colored_box
    - use_decorated_box
    - use_full_hex_values_for_flutter_colors
    - use_function_type_syntax_for_parameters
    - use_if_null_to_convert_nulls_to_booleans
    - use_is_even_rather_than_modulo
    - use_key_in_widget_constructors
    - use_late_for_private_fields_and_variables
    - use_rethrow_when_possible
    - use_setters_to_change_properties
    - use_string_buffers
    - use_super_parameters
    - use_test_throws_matchers
    - valid_regexps
```

### No `// ignore:` Without Justification

```dart
// ✅ GOOD: Justified ignore with comment
// ignore: unnecessary_null_checks — false positive due to legacy API
if (value != null) { ... }

// ❌ BAD: Silent ignore
// ignore: unused_local_variable
final x = 1;
```

---

## 5.3 Formatting

```bash
melos run format:check  # CI gate — verifies `dart format` compliance
melos run format        # Auto-fix locally — run before commit
```

**Standard:** `dart format` (2-space indent, 80-char line wrap, trailing commas)

---

## 5.4 Package Health (pana)

```bash
melos run pana  # Targets 160/160 points for ALL 5 packages
```

### pana Score Breakdown (160 max)

| Category | Max Points | Key Checks |
|----------|------------|------------|
| Dart file conventions | 30 | pubspec.yaml, README.md, CHANGELOG.md, license |
| Documentation | 20 | 20%+ public API documented, example exists |
| Platform support | 20 | Declares platforms (android, ios, etc.) |
| Static analysis | 50 | 0 issues from `dart analyze` |
| Dependencies | 40 | All deps at latest compatible, lower bounds work |

### Common pana Pitfalls

| Issue | Fix |
|-------|-----|
| Missing CHANGELOG entry for version | Add entry in `CHANGELOG.md` |
| Example app analyze fails | Fix example app code |
| Dependencies not latest | `flutter pub upgrade` (within constraints) |
| Platform declarations missing | Adapters inherit core's `platforms: [android, ios]` |
| License not OSI-approved | Ensure MIT/BSD/Apache-2.0 |
| dartdoc warnings | Document public APIs |

---

## 5.5 Test Requirements

### Test Types & Locations

| Type | Location | When Required |
|------|----------|---------------|
| Unit | `packages/*/test/` | Every new public method, edge case |
| Widget | `packages/interceptly/test/ui/` | UI component changes |
| Integration/E2E | `packages/interceptly/test/e2e/` | Cross-feature flows |
| Stress | `packages/interceptly/test/stress/` | Performance-sensitive changes |
| Adapter contract | `packages/*/test/` | Must verify SPI delegation |

### Test Patterns

#### 1. Session Lifecycle — ALWAYS Reset

```dart
setUp(() async {
  await InspectorSession.resetForTesting();  // CRITICAL for isolate isolation
  session.configureSession(settings);
  await session.initialize();
});

tearDown(() async {
  await InspectorSession.resetForTesting();
});
```

#### 2. Time-Dependent Logic — Use `fake_async`

```dart
test('pending timeout marks request failed', () async {
  final fake = FakeAsync();
  fake.run((async) {
    session.record(capture);
    async.elapse(const Duration(seconds: 50)); // > pendingTimeout (45s)
    expect(session.entries.first.status, 'timeout');
  });
});
```

#### 3. Adapter Tests — Verify SPI Delegation

```dart
test('Dio interceptor delegates to collector', () async {
  final spy = SpyHttpCollector();
  final interceptor = InterceptlyDioInterceptor(spy);
  
  // Trigger request...
  
  verify(spy.begin(...)).called(1);
  // DON'T test internal logic — that's core's job
});
```

#### 4. Stress Tests — Tag Appropriately

```dart
@Tags(['stress'])
test('handles 1000 concurrent requests', () async { ... });
```

---

## 5.6 CI Pipeline Requirements

### `ci.yml` Jobs

| Job | Runs | Must Pass |
|-----|------|-----------|
| `lint-and-format` | `format:check`, `analyze` | 0 issues |
| `test` | `melos run coverage` | All tests pass, coverage uploaded |
| `pana-and-example` | `melos run pana`, example `analyze` + `test` | 160/160, example clean |

### Coverage Target

- No hard threshold, but **don't decrease** existing coverage
- New code should be tested

---

## 5.7 Local Verification Checklist

Before pushing:

```bash
# 1. Format
melos run format

# 2. Analyze
melos run analyze

# 3. Core tests (fast)
melos run test:core

# 4. Full gate
melos run check

# 5. Optional: pana (slow)
melos run pana
```

---

## 5.8 Quality Gate Summary

| Gate | Command | Tolerance |
|------|---------|-----------|
| Format | `melos run format:check` | 0 changes needed |
| Analysis | `melos run analyze` | 0 issues |
| Core Tests | `melos run test:core` | 100% pass |
| pana | `melos run pana` | 160/160 all packages |
| Full | `melos run check` | All above |

**Rule:** If any gate fails locally, it WILL fail on CI. Fix locally first.