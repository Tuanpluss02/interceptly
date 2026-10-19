import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/ui/format.dart';

void main() {
  group('formatBytes', () {
    test('formats 0B boundary', () {
      expect(formatBytes(0), '0 B');
    });

    test('formats negative bytes gracefully as 0 B', () {
      expect(formatBytes(-10), '0 B');
    });

    test('formats 1023B boundary', () {
      expect(formatBytes(1023), '1023 B');
    });

    test('formats 1KB boundary', () {
      expect(formatBytes(1024), '1.0 KB');
    });

    test('formats fractional KB', () {
      expect(formatBytes(1536), '1.5 KB');
    });

    test('formats 1MB boundary', () {
      expect(formatBytes(1024 * 1024), '1.0 MB');
    });

    test('formats 1.5MB boundary', () {
      expect(formatBytes((1.5 * 1024 * 1024).round()), '1.5 MB');
    });

    test('formats 1GB boundary', () {
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
    });

    test('formats 2GB boundary', () {
      expect(formatBytes(2 * 1024 * 1024 * 1024), '2.0 GB');
    });
  });

  group('formatDuration', () {
    test('formats 0 duration', () {
      expect(formatDuration(Duration.zero), '0ms');
    });

    test('formats negative duration gracefully', () {
      expect(formatDuration(const Duration(milliseconds: -100)), '0ms');
    });

    test('formats milliseconds', () {
      expect(formatDuration(const Duration(milliseconds: 350)), '350ms');
    });

    test('formats seconds', () {
      expect(formatDuration(const Duration(seconds: 45)), '45s');
    });

    test('formats minutes and seconds', () {
      expect(formatDuration(const Duration(minutes: 2, seconds: 15)), '2m 15s');
      expect(formatDuration(const Duration(minutes: 5)), '5m');
    });

    test('formats hours and minutes', () {
      expect(formatDuration(const Duration(hours: 1, minutes: 23)), '1h 23m');
      expect(formatDuration(const Duration(hours: 2)), '2h');
    });
  });
}
