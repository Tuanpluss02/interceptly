import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/session/grouping_controller.dart';

void main() {
  late GroupingController controller;

  setUp(() => controller = GroupingController());
  tearDown(() => controller.dispose());

  // ── initial state ─────────────────────────────────────────────────────────

  test('enabled defaults to false', () {
    expect(controller.enabled, isFalse);
  });

  test('isExpanded defaults to true for unknown domain', () {
    expect(controller.isExpanded('example.com'), isTrue);
  });

  // ── setEnabled ────────────────────────────────────────────────────────────

  group('GroupingController.setEnabled', () {
    test('toggles enabled state', () {
      controller.setEnabled(true);
      expect(controller.enabled, isTrue);

      controller.setEnabled(false);
      expect(controller.enabled, isFalse);
    });

    test('notifies listeners on change', () {
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.setEnabled(true);
      expect(notifyCount, 1);
    });

    test('does not notify when value is unchanged', () {
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.setEnabled(false); // already false
      expect(notifyCount, 0);
    });
  });

  // ── toggleDomainExpanded ──────────────────────────────────────────────────

  group('GroupingController.toggleDomainExpanded', () {
    test('first toggle collapses a domain (default was expanded)', () {
      controller.toggleDomainExpanded('example.com');
      expect(controller.isExpanded('example.com'), isFalse);
    });

    test('second toggle re-expands the domain', () {
      controller.toggleDomainExpanded('example.com');
      controller.toggleDomainExpanded('example.com');
      expect(controller.isExpanded('example.com'), isTrue);
    });

    test('notifies listeners on toggle', () {
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.toggleDomainExpanded('example.com');
      expect(notifyCount, 1);
    });

    test('different domains have independent state', () {
      controller.toggleDomainExpanded('a.com');
      expect(controller.isExpanded('a.com'), isFalse);
      expect(controller.isExpanded('b.com'), isTrue);
    });
  });

  // ── reset ─────────────────────────────────────────────────────────────────

  group('GroupingController.reset', () {
    test('clears collapsed domains, restoring defaults', () {
      controller.toggleDomainExpanded('example.com'); // collapse it
      expect(controller.isExpanded('example.com'), isFalse);

      controller.reset();
      expect(controller.isExpanded('example.com'), isTrue);
    });

    test('does not affect enabled flag', () {
      controller.setEnabled(true);
      controller.reset();
      expect(controller.enabled, isTrue);
    });
  });
}
