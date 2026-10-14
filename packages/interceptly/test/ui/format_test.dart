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
}
