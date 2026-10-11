import 'package:flutter/foundation.dart';

/// Runs [body] and swallows any error it throws.
///
/// Capture code must never break the host app's request: an inspector that
/// turns a successful request into a failure is worse than no inspector.
/// Every adapter wraps its bookkeeping in this guard.
T? guardCapture<T>(T Function() body) {
  try {
    return body();
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[Interceptly] capture failed (request unaffected): $e\n$st');
    }
    return null;
  }
}

Future<T?> guardCaptureAsync<T>(Future<T> Function() body) async {
  try {
    return await body();
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[Interceptly] capture failed (request unaffected): $e\n$st');
    }
    return null;
  }
}

/// Case-insensitive header lookup.
String? headerValue(Map<String, String> headers, String name) {
  final lower = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value;
  }
  return null;
}

/// Utility class for safe capture guards and header sanitization.
abstract final class CaptureGuard {
  /// Redacts sensitive headers defined in [redactedKeys] (compared case-insensitively).
  ///
  /// For optimal performance, [redactedKeys] should be pre-normalized to lowercase.
  static Map<String, String> redactHeaders(
    Map<String, String> headers,
    Set<String> redactedKeys,
  ) {
    if (redactedKeys.isEmpty) return headers;
    return headers.map((k, v) {
      if (redactedKeys.contains(k.toLowerCase())) {
        return MapEntry(k, '[REDACTED]');
      }
      return MapEntry(k, v);
    });
  }
}

/// Redacts sensitive headers defined in [redactedKeys] (compared case-insensitively).
///
/// For optimal performance, [redactedKeys] should be pre-normalized to lowercase.
Map<String, String> redactHeaders(
  Map<String, String> headers,
  Set<String> redactedKeys,
) =>
    CaptureGuard.redactHeaders(headers, redactedKeys);
