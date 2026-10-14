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

  /// Masks query parameter values listed in [redactedQueryParams] with `[REDACTED]`.
  ///
  /// Matching is case-insensitive. An empty set returns [url] unchanged, so
  /// default settings keep capture behavior byte-identical. URLs without a
  /// matching parameter are returned unchanged to avoid re-encoding drift.
  static String sanitizeUrl(
    String url, [
    Set<String> redactedQueryParams = const {},
  ]) {
    if (redactedQueryParams.isEmpty) return url;
    final normalized =
        redactedQueryParams.map((k) => k.toLowerCase()).toSet();
    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return url;
    }
    if (!uri.hasQuery) return url;
    final params = uri.queryParametersAll;
    var matched = false;
    final masked = <String, List<String>>{};
    for (final entry in params.entries) {
      if (normalized.contains(entry.key.toLowerCase())) {
        matched = true;
        masked[entry.key] = entry.value.map((_) => '[REDACTED]').toList();
      } else {
        masked[entry.key] = entry.value;
      }
    }
    if (!matched) return url;
    return uri.replace(queryParameters: masked).toString();
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

/// Masks query parameter values listed in [redactedQueryParams] with `[REDACTED]`.
///
/// Matching is case-insensitive. An empty set returns [url] unchanged.
String sanitizeUrl(
  String url, [
  Set<String> redactedQueryParams = const {},
]) =>
    CaptureGuard.sanitizeUrl(url, redactedQueryParams);
