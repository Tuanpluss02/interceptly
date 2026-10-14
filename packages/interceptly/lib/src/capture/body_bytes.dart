import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Encodes an arbitrary request or response body into raw [Uint8List] bytes.
///
/// Handles:
/// - `null`: returns null.
/// - [Uint8List]: returns unmodified bytes.
/// - [List<int>]: wraps into [Uint8List].
/// - [String]: encodes via UTF-8.
/// - [Map] or [List]: encodes via JSON serialization then UTF-8. Falls back
///   to string representation if JSON serialization throws.
/// - [Stream]: formats placeholder byte representation without consuming the stream.
/// - Fallback: encodes `body.toString()` via UTF-8.
Uint8List? encodeBodyBytes(Object? body) {
  if (body == null) return null;
  if (body is Uint8List) return body;
  if (body is List<int>) return Uint8List.fromList(body);
  if (body is String) return utf8.encode(body);
  if (body is Stream) {
    return utf8.encode('[streamed body]');
  }
  if (body is Map || body is List) {
    try {
      return utf8.encode(jsonEncode(body));
    } catch (_) {
      try {
        return utf8.encode(body.toString());
      } catch (_) {
        return null;
      }
    }
  }
  try {
    return utf8.encode(body.toString());
  } catch (_) {
    return null;
  }
}

/// Normalizes a dynamic or multi-value header map into a string-only map.
Map<String, String> normalizeHeaders(Map<String, Object?> headers) {
  return headers.map((key, value) {
    if (value is Iterable) {
      return MapEntry(key, value.join(', '));
    }
    return MapEntry(key, value?.toString() ?? '');
  });
}

/// Maps a headers map into a list of key-value maps with specified field names.
List<Map<String, String>> mapHeaderEntries(
  Map<String, String> headers, {
  String keyName = 'name',
  String valueName = 'value',
}) {
  return headers.entries
      .map((entry) => {keyName: entry.key, valueName: entry.value})
      .toList();
}
