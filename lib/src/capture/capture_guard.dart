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

/// Redacts sensitive headers defined in [redactedKeys] (compared case-insensitively).
Map<String, String> redactHeaders(
  Map<String, String> headers,
  Set<String> redactedKeys,
) {
  if (redactedKeys.isEmpty) return headers;
  final lowerKeys = redactedKeys.map((k) => k.toLowerCase()).toSet();
  return headers.map((k, v) {
    if (lowerKeys.contains(k.toLowerCase())) {
      return MapEntry(k, '[REDACTED]');
    }
    return MapEntry(k, v);
  });
}
