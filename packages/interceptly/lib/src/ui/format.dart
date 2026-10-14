/// Single-source utility for formatting byte sizes with consistent precision.
library;

/// Formats a byte count into a human-readable string with unified precision.
///
/// Precision rules:
/// - Byte unit (B): exact integer without decimal point (e.g. `'0 B'`, `'1023 B'`).
/// - Kilobyte unit (KB): one decimal place (e.g. `'1.0 KB'`, `'1.5 KB'`).
/// - Megabyte unit (MB): one decimal place (e.g. `'1.0 MB'`, `'1.5 MB'`).
/// - Gigabyte unit (GB): one decimal place (e.g. `'1.0 GB'`, `'2.0 GB'`).
///
/// Negative values are gracefully normalized to `'0 B'`.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
