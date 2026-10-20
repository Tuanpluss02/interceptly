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
  static const int computeThreshold = 100 * 1024;

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
      } catch (_) {}
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
      if (b == 0) return true;
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
  /// If [maxBody] <= 0 (unlimited) or [bytes.length] <= [maxBody],
  /// the full buffer is returned unchanged.
  static Uint8List? truncate(Uint8List? bytes, int maxBody, int previewLen) {
    if (bytes == null || bytes.isEmpty) return null;
    if (maxBody <= 0 || bytes.length <= maxBody) return bytes;
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
      final isTruncated = offset < raw.length && raw[offset] == 1;
      return (req, res, isTruncated);
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

  /// Attempts to repair an incomplete or truncated JSON string by auto-closing
  /// open strings, removing trailing delimiters, and balancing unclosed
  /// object/array brackets using a stack-based algorithm.
  ///
  /// Returns a valid JSON string if repair succeeded and decoded cleanly,
  /// or `null` if the input is not JSON or cannot be repaired.
  static String? repairTruncatedJson(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
      return null;
    }

    final len = trimmed.length;
    final stack = <int>[];
    bool inString = false;
    bool isEscaped = false;
    int lastDelimiter = -1;

    for (int i = 0; i < len; i++) {
      final c = trimmed.codeUnitAt(i);
      if (inString) {
        if (isEscaped) {
          isEscaped = false;
        } else if (c == 0x5C) {
          isEscaped = true;
        } else if (c == 0x22) {
          inString = false;
        }
      } else {
        if (c == 0x22) {
          inString = true;
        } else if (c == 0x7B) {
          stack.add(0x7D);
          lastDelimiter = c;
        } else if (c == 0x5B) {
          stack.add(0x5D);
          lastDelimiter = c;
        } else if (c == 0x7D) {
          if (stack.isNotEmpty && stack.last == 0x7D) stack.removeLast();
          lastDelimiter = c;
        } else if (c == 0x5D) {
          if (stack.isNotEmpty && stack.last == 0x5D) stack.removeLast();
          lastDelimiter = c;
        } else if (c == 0x3A || c == 0x2C) {
          lastDelimiter = c;
        }
      }
    }

    final buf = StringBuffer();
    var body = trimmed;

    if (inString) {
      if (isEscaped) {
        body = body.substring(0, body.length - 1);
      }
      buf.write(body);
      buf.write('"');
      if (stack.isNotEmpty && stack.last == 0x7D && lastDelimiter != 0x3A) {
        buf.write(': null');
      }
    } else {
      var s = body.trimRight();
      if (s.endsWith(',')) {
        s = s.substring(0, s.length - 1).trimRight();
      } else if (s.endsWith(':')) {
        s = '$s null';
      } else if (s.endsWith('.')) {
        s = '${s}0';
      } else if (s.endsWith('-') ||
          s.endsWith('+') ||
          s.toLowerCase().endsWith('e')) {
        s = '${s}0';
      } else {
        final lastWordMatch = RegExp(r'[a-zA-Z]+$').firstMatch(s);
        if (lastWordMatch != null) {
          final word = lastWordMatch.group(0)!.toLowerCase();
          if ('true'.startsWith(word)) {
            s = '${s.substring(0, s.length - word.length)}true';
          } else if ('false'.startsWith(word)) {
            s = '${s.substring(0, s.length - word.length)}false';
          } else if ('null'.startsWith(word)) {
            s = '${s.substring(0, s.length - word.length)}null';
          } else {
            if (stack.isNotEmpty &&
                stack.last == 0x7D &&
                lastDelimiter != 0x3A) {
              s = s.substring(0, s.length - word.length);
              if (s.trimRight().endsWith(',')) {
                s = s.trimRight();
                s = s.substring(0, s.length - 1).trimRight();
              }
            }
          }
        }
      }
      buf.write(s);
    }

    while (stack.isNotEmpty) {
      buf.writeCharCode(stack.removeLast());
    }

    final candidate = buf.toString();
    try {
      jsonDecode(candidate);
      return candidate;
    } catch (_) {
      return null;
    }
  }

  /// Safely decodes [text] as JSON, attempting auto-repair if [text] is
  /// truncated. Returns the decoded [Map], [List], or primitive if valid,
  /// otherwise returns the original [text] unchanged.
  static dynamic decodeJsonLenient(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      final repaired = repairTruncatedJson(text);
      if (repaired != null) {
        try {
          return jsonDecode(repaired);
        } catch (_) {}
      }
      return text;
    }
  }
}

/// Standalone helper so [compute] can spawn the isolate with a top-level
/// function (it cannot capture instance methods).
String? _utf8DecodeOnly(Uint8List bytes) {
  return BodyDecodeService.tryUtf8(bytes);
}
