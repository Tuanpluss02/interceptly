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

  // Null byte prefix — guaranteed to never appear in real text or JSON bodies.
  static const String _placeholderPrefix = '\x00';

  /// Placeholder used when a file-backed body cannot be read.
  static const String unavailablePlaceholder =
      '$_placeholderPrefix[body unavailable]';

  /// Returns true if [body] is a placeholder string, not real body content.
  ///
  /// Use this instead of `body.startsWith('[')` to avoid false-positives on
  /// legitimate JSON array bodies like `[{"id":1}]`.
  static bool isPlaceholder(String body) => body.startsWith(_placeholderPrefix);

  /// Decodes [bytes] to a UTF-8 string, or returns a binary placeholder.
  ///
  /// Returns `null` when [bytes] is null or empty.
  ///
  /// For payloads above [computeThreshold] the UTF-8 decode is pushed to a
  /// background isolate to avoid blocking the main thread. Smaller payloads
  /// are decoded inline because isolate spawn overhead dwarfs the savings.
  static Future<String?> decodeAsync(
    Uint8List? bytes,
    String? contentType,
  ) async {
    if (bytes == null || bytes.isEmpty) return null;
    if (isBinary(contentType)) {
      return '$_placeholderPrefix[binary: ${bytes.length} bytes]';
    }
    if (bytes.length > computeThreshold) {
      try {
        return await compute(_utf8DecodeOnly, bytes);
      } catch (_) {
        // Fall through to inline decode below.
      }
    }
    return _decodeInline(bytes);
  }

  /// Synchronous variant kept for callers that can't await (init paths).
  static String? decode(Uint8List? bytes, String? contentType) {
    if (bytes == null || bytes.isEmpty) return null;
    if (isBinary(contentType)) {
      return '$_placeholderPrefix[binary: ${bytes.length} bytes]';
    }
    return _decodeInline(bytes);
  }

  static String? _decodeInline(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return '$_placeholderPrefix[binary: ${bytes.length} bytes]';
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
    final parts = _unpack(raw);
    if (parts == null) return (null, null, false);
    return (
      parts.$1 != null ? tryUtf8(parts.$1!) : null,
      parts.$2 != null ? tryUtf8(parts.$2!) : null,
      parts.$3,
    );
  }

  /// Unpacks a packed body record from [raw] into raw byte arrays.
  ///
  /// Returns `(requestBytes, responseBytes, isTruncated)`.
  /// Used when loading the detail view.
  static (Uint8List?, Uint8List?, bool) unpackToBytes(Uint8List raw) {
    final parts = _unpack(raw);
    if (parts == null) return (null, null, false);
    return parts;
  }

  static (Uint8List?, Uint8List?, bool)? _unpack(Uint8List raw) {
    try {
      final data = ByteData.sublistView(raw);
      var offset = 0;
      Uint8List? readPart() {
        if (offset + 4 > raw.length) throw const FormatException();
        final len = data.getUint32(offset, Endian.big);
        offset += 4;
        if (len == 0xFFFFFFFF) return null;
        if (offset + len > raw.length) throw const FormatException();
        final part = raw.sublist(offset, offset + len);
        offset += len;
        return part;
      }

      final req = readPart();
      final res = readPart();
      if (offset + 1 > raw.length) throw const FormatException();
      return (req, res, raw[offset] == 1);
    } catch (_) {
      return null;
    }
  }

  /// Decodes [bytes] as UTF-8, or returns a binary placeholder on failure.
  static String tryUtf8(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return '$_placeholderPrefix[binary: ${bytes.length} bytes]';
    }
  }
}

/// Standalone helper so [compute] can spawn the isolate with a top-level
/// function (it cannot capture instance methods).
String? _utf8DecodeOnly(Uint8List bytes) {
  return BodyDecodeService.tryUtf8(bytes);
}
