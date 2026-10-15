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

/// Formats a [Duration] into a compact, human-readable string.
///
/// Examples:
/// - `< 1000ms`: `'350ms'`
/// - `< 60s`: `'45s'`
/// - `< 60m`: `'2m 15s'` or `'2m'`
/// - `>= 1h`: `'1h 23m'` or `'1h'`
String formatDuration(Duration duration) {
  if (duration.isNegative || duration == Duration.zero) return '0ms';
  final ms = duration.inMilliseconds;
  if (ms < 1000) return '${ms}ms';
  final seconds = duration.inSeconds;
  if (seconds < 60) return '${seconds}s';
  final minutes = duration.inMinutes;
  final remainingSeconds = seconds % 60;
  if (minutes < 60) {
    return remainingSeconds > 0
        ? '${minutes}m ${remainingSeconds}s'
        : '${minutes}m';
  }
  final hours = duration.inHours;
  final remainingMinutes = minutes % 60;
  return remainingMinutes > 0 ? '${hours}h ${remainingMinutes}m' : '${hours}h';
}
