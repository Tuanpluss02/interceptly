import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';

void main() {
  group('InterceptlySettings assertions', () {
    test('asserts on non-positive capacities', () {
      expect(() => InterceptlySettings(maxEntries: 0), throwsAssertionError);
      expect(() => InterceptlySettings(maxEntries: -1), throwsAssertionError);
      expect(
          () => InterceptlySettings(maxQueuedEvents: 0), throwsAssertionError);
      expect(
          () => InterceptlySettings(maxQueuedEvents: -1), throwsAssertionError);
      expect(() => InterceptlySettings(maxFramesPerSession: 0),
          throwsAssertionError);
      expect(() => InterceptlySettings(maxFramesPerSession: -1),
          throwsAssertionError);
      expect(() => InterceptlySettings(bodyOffloadThreshold: -1),
          throwsAssertionError);
      expect(() => InterceptlySettings(previewTruncationBytes: -1),
          throwsAssertionError);
      expect(() => InterceptlySettings(maxUiPreviewBytes: -1),
          throwsAssertionError);
    });

    test('allows non-negative boundary values for byte thresholds', () {
      expect(
        () => const InterceptlySettings(
          previewTruncationBytes: 0,
          bodyOffloadThreshold: 0,
          maxUiPreviewBytes: 0,
        ),
        returnsNormally,
      );
    });

    test('default configuration initializes with valid bounds', () {
      const settings = InterceptlySettings();
      expect(settings.maxEntries, greaterThan(0));
      expect(settings.maxQueuedEvents, greaterThan(0));
      expect(settings.maxFramesPerSession, greaterThan(0));
      expect(settings.previewTruncationBytes, greaterThanOrEqualTo(0));
      expect(settings.bodyOffloadThreshold, greaterThanOrEqualTo(0));
      expect(settings.maxUiPreviewBytes, greaterThanOrEqualTo(0));
    });

    test('copyWith enforces assertions on updated values', () {
      const settings = InterceptlySettings();
      expect(() => settings.copyWith(maxEntries: 0), throwsAssertionError);
      expect(() => settings.copyWith(maxQueuedEvents: 0), throwsAssertionError);
      expect(() => settings.copyWith(maxFramesPerSession: 0),
          throwsAssertionError);
      expect(() => settings.copyWith(bodyOffloadThreshold: -1),
          throwsAssertionError);
      expect(() => settings.copyWith(previewTruncationBytes: -1),
          throwsAssertionError);
      expect(
          () => settings.copyWith(maxUiPreviewBytes: -1), throwsAssertionError);
    });
  });
}
