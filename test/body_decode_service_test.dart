import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/session/body_decode_service.dart';

void main() {
  // ── decode ────────────────────────────────────────────────────────────────

  group('BodyDecodeService.decode', () {
    test('returns null for null bytes', () {
      expect(BodyDecodeService.decode(null, null), isNull);
    });

    test('returns null for empty bytes', () {
      expect(BodyDecodeService.decode(Uint8List(0), null), isNull);
    });

    test('returns UTF-8 string for text content', () {
      final bytes = Uint8List.fromList(utf8.encode('hello world'));
      expect(BodyDecodeService.decode(bytes, 'application/json'), 'hello world');
    });

    test('returns binary placeholder for image content type', () {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF]);
      final result = BodyDecodeService.decode(bytes, 'image/jpeg');
      expect(result, '[binary: 3 bytes]');
    });

    test('returns binary placeholder when bytes fail UTF-8 decode', () {
      final bytes = Uint8List.fromList([0xFF, 0xFE]); // invalid UTF-8
      final result = BodyDecodeService.decode(bytes, 'text/plain');
      expect(result, startsWith('[binary:'));
    });
  });

  // ── isBinary ──────────────────────────────────────────────────────────────

  group('BodyDecodeService.isBinary', () {
    test('returns false for null content type', () {
      expect(BodyDecodeService.isBinary(null), isFalse);
    });

    test('returns false for text/plain', () {
      expect(BodyDecodeService.isBinary('text/plain'), isFalse);
    });

    test('returns false for application/json', () {
      expect(BodyDecodeService.isBinary('application/json'), isFalse);
    });

    test('returns true for image types', () {
      expect(BodyDecodeService.isBinary('image/png'), isTrue);
      expect(BodyDecodeService.isBinary('image/jpeg'), isTrue);
    });

    test('returns true for audio types', () {
      expect(BodyDecodeService.isBinary('audio/mpeg'), isTrue);
    });

    test('returns true for video types', () {
      expect(BodyDecodeService.isBinary('video/mp4'), isTrue);
    });

    test('returns true for application/pdf', () {
      expect(BodyDecodeService.isBinary('application/pdf'), isTrue);
    });

    test('returns true for application/octet-stream', () {
      expect(BodyDecodeService.isBinary('application/octet-stream'), isTrue);
    });

    test('returns true for application/zip', () {
      expect(BodyDecodeService.isBinary('application/zip'), isTrue);
    });
  });

  // ── truncate ──────────────────────────────────────────────────────────────

  group('BodyDecodeService.truncate', () {
    test('returns null for null bytes', () {
      expect(BodyDecodeService.truncate(null, 1000, 500), isNull);
    });

    test('returns null for empty bytes', () {
      expect(BodyDecodeService.truncate(Uint8List(0), 1000, 500), isNull);
    });

    test('returns unchanged when within maxBody', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final result = BodyDecodeService.truncate(bytes, 10, 5);
      expect(result, bytes);
    });

    test('truncates to previewLen when exceeding maxBody', () {
      final bytes = Uint8List.fromList(List.generate(20, (i) => i));
      final result = BodyDecodeService.truncate(bytes, 10, 5)!;
      expect(result.length, 5);
      expect(result, [0, 1, 2, 3, 4]);
    });

    test('does not exceed available bytes when previewLen > length', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final result = BodyDecodeService.truncate(bytes, 2, 100)!;
      expect(result.length, 3); // min(previewLen, bytes.length) = 3
    });
  });

  // ── tryUtf8 ───────────────────────────────────────────────────────────────

  group('BodyDecodeService.tryUtf8', () {
    test('decodes valid UTF-8', () {
      final bytes = Uint8List.fromList(utf8.encode('hello'));
      expect(BodyDecodeService.tryUtf8(bytes), 'hello');
    });

    test('returns binary placeholder for invalid UTF-8', () {
      final bytes = Uint8List.fromList([0xFF, 0xFE]);
      expect(BodyDecodeService.tryUtf8(bytes), '[binary: 2 bytes]');
    });
  });

  // ── unpackToText ──────────────────────────────────────────────────────────

  group('BodyDecodeService.unpackToText', () {
    test('decodes packed req/res bodies to text', () {
      final packed = _packBodies('{"id":1}', '{"ok":true}');
      final (req, res, truncated) = BodyDecodeService.unpackToText(packed);
      expect(req, '{"id":1}');
      expect(res, '{"ok":true}');
      expect(truncated, isFalse);
    });

    test('returns nulls for missing fields', () {
      final packed = _packBodiesPartial(req: null, res: '{"ok":true}');
      final (req, res, _) = BodyDecodeService.unpackToText(packed);
      expect(req, isNull);
      expect(res, '{"ok":true}');
    });

    test('respects truncated flag', () {
      final packed = _packBodies('body', 'resp', truncated: true);
      final (_, _, truncated) = BodyDecodeService.unpackToText(packed);
      expect(truncated, isTrue);
    });

    test('returns (null, null, false) for malformed raw bytes', () {
      final (req, res, truncated) = BodyDecodeService.unpackToText(Uint8List.fromList([1, 2, 3]));
      expect(req, isNull);
      expect(res, isNull);
      expect(truncated, isFalse);
    });
  });

  // ── unpackToBytes ─────────────────────────────────────────────────────────

  group('BodyDecodeService.unpackToBytes', () {
    test('decodes packed req/res bodies to bytes', () {
      final reqText = '{"id":1}';
      final resText = '{"ok":true}';
      final packed = _packBodies(reqText, resText);
      final (reqBytes, resBytes, truncated) = BodyDecodeService.unpackToBytes(packed);
      expect(utf8.decode(reqBytes!), reqText);
      expect(utf8.decode(resBytes!), resText);
      expect(truncated, isFalse);
    });

    test('returns (null, null, false) for malformed raw bytes', () {
      final (req, res, truncated) = BodyDecodeService.unpackToBytes(Uint8List.fromList([0xFF]));
      expect(req, isNull);
      expect(res, isNull);
      expect(truncated, isFalse);
    });
  });
}

/// Builds a packed body record in the format that BodyDecodeService expects.
Uint8List _packBodies(String req, String res, {bool truncated = false}) {
  final json = jsonEncode({
    'req': base64.encode(utf8.encode(req)),
    'res': base64.encode(utf8.encode(res)),
    'truncated': truncated,
  });
  return Uint8List.fromList(utf8.encode(json));
}

Uint8List _packBodiesPartial({String? req, String? res, bool truncated = false}) {
  final map = <String, dynamic>{'truncated': truncated};
  if (req != null) map['req'] = base64.encode(utf8.encode(req));
  if (res != null) map['res'] = base64.encode(utf8.encode(res));
  return Uint8List.fromList(utf8.encode(jsonEncode(map)));
}
