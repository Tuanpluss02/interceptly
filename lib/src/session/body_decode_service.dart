import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Pure-static helpers for decoding and unpacking request/response bodies.
///
/// All methods are safe to call from the main isolate. Methods that operate
/// on large buffers delegate to a background isolate via [compute].
class BodyDecodeService {
  BodyDecodeService._();

  /// Bodies larger than this are decoded in a background isolate via [compute]
  /// to avoid blocking the main thread for tens of milliseconds.
  static const int computeThreshold = 100 * 1024; // 100 KB

  /// Decodes [bytes] to a UTF-8 string, or returns a binary placeholder.
  ///
  /// Returns `null` when [bytes] is null or empty.
  static String? decode(Uint8List? bytes, String? contentType) {
    if (bytes == null || bytes.isEmpty) return null;
    if (isBinary(contentType)) return '[binary: ${bytes.length} bytes]';
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return '[binary: ${bytes.length} bytes]';
    }
  }

  /// Returns true if [contentType] indicates non-text (image, audio, etc.).
  static bool isBinary(String? contentType) {
    if (contentType == null) return false;
    return contentType.startsWith('image/') ||
        contentType.startsWith('audio/') ||
        contentType.startsWith('video/') ||
        contentType.contains('application/pdf') ||
        contentType.contains('application/octet-stream') ||
        contentType.contains('application/zip');
  }

  /// Returns a preview of [bytes] truncated to [previewLen] bytes,
  /// or `null` when [bytes] is null or empty.
  ///
  /// If [bytes.length] <= [maxBody] the full buffer is returned unchanged.
  static Uint8List? truncate(Uint8List? bytes, int maxBody, int previewLen) {
    if (bytes == null || bytes.isEmpty) return null;
    if (bytes.length <= maxBody) return bytes;
    final end = previewLen < bytes.length ? previewLen : bytes.length;
    return bytes.sublist(0, end);
  }

  /// Unpacks a packed body record from [raw] into decoded text strings.
  ///
  /// Returns `(requestText, responseText, isTruncated)`.
  /// Used for in-memory body search where text is sufficient.
  static (String?, String?, bool) unpackToText(Uint8List raw) {
    try {
      final json = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      final reqB64 = json['req'] as String?;
      final resB64 = json['res'] as String?;
      final truncated = json['truncated'] as bool? ?? false;
      return (
        reqB64 != null ? tryUtf8(base64.decode(reqB64)) : null,
        resB64 != null ? tryUtf8(base64.decode(resB64)) : null,
        truncated,
      );
    } catch (_) {
      return (null, null, false);
    }
  }

  /// Unpacks a packed body record from [raw] into raw byte arrays.
  ///
  /// Returns `(requestBytes, responseBytes, isTruncated)`.
  /// Used when loading the detail view.
  static (Uint8List?, Uint8List?, bool) unpackToBytes(Uint8List raw) {
    try {
      final json = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      final reqB64 = json['req'] as String?;
      final resB64 = json['res'] as String?;
      final truncated = json['truncated'] as bool? ?? false;
      return (
        reqB64 != null ? base64.decode(reqB64) : null,
        resB64 != null ? base64.decode(resB64) : null,
        truncated,
      );
    } catch (_) {
      return (null, null, false);
    }
  }

  /// Decodes [bytes] as UTF-8, or returns a binary placeholder on failure.
  static String tryUtf8(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return '[binary: ${bytes.length} bytes]';
    }
  }
}
