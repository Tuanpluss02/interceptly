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
    if (_looksBinary(bytes)) {
      return '$_placeholderPrefix[binary: ${bytes.length} bytes]';
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      // Check if it's text that was cut mid-character:
      // Try decoding up to last few bytes trimmed (up to 3 bytes for multi-byte UTF-8).
      final trimmed = _trimTruncatedUtf8(bytes);
      if (trimmed != null) {
        return utf8.decode(trimmed);
      }
      return '$_placeholderPrefix[binary: ${bytes.length} bytes]';
    }
  }

  static Uint8List? _trimTruncatedUtf8(Uint8List bytes) {
    for (var trim = 1; trim <= 3 && trim < bytes.length; trim++) {
      try {
        final sub = Uint8List.sublistView(bytes, 0, bytes.length - trim);
        utf8.decode(sub);
        return sub;
      } catch (_) {}
    }
    return null;
  }

  /// Checks if arbitrary bytes look like non-text binary data by checking null bytes
  /// or high ratio of non-printable control characters.
  static bool _looksBinary(Uint8List bytes) {
    final checkLen = bytes.length < 512 ? bytes.length : 512;
    int unprintable = 0;
    for (var i = 0; i < checkLen; i++) {
      final b = bytes[i];
      if (b == 0) return true; // Null byte in text is almost always binary
      // Control chars other than tab (9), LF (10), CR (13)
      if (b < 9 || (b > 10 && b < 13) || (b > 13 && b < 32)) {
        unprintable++;
      }
    }
    return unprintable > (checkLen * 0.1);
  }

  /// Returns true if [contentType] indicates non-text (image, audio, etc.).
  static bool isBinary(String? contentType) {
    if (contentType == null) return false;
    final lower = contentType.toLowerCase();
    return lower.startsWith('image/') ||
        lower.startsWith('audio/') ||
        lower.startsWith('video/') ||
        lower.startsWith('font/') ||
        lower.contains('application/pdf') ||
        lower.contains('application/octet-stream') ||
        lower.contains('application/zip') ||
        lower.contains('application/gzip') ||
        lower.contains('application/x-protobuf');
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
    if (_looksBinary(bytes)) {
      return '$_placeholderPrefix[binary: ${bytes.length} bytes]';
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      final trimmed = _trimTruncatedUtf8(bytes);
      if (trimmed != null) {
        return utf8.decode(trimmed);
      }
      return '$_placeholderPrefix[binary: ${bytes.length} bytes]';
    }
  }
}

/// Standalone helper so [compute] can spawn the isolate with a top-level
/// function (it cannot capture instance methods).
String? _utf8DecodeOnly(Uint8List bytes) {
  return BodyDecodeService.tryUtf8(bytes);
}
