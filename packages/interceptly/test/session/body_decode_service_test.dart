// ignore_for_file: invalid_use_of_internal_member

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/engine/body_decode_service.dart';

void main() {
  group('BodyDecodeService.decode', () {
    test('returns null for null bytes', () {
      expect(BodyDecodeService.decode(null, null), isNull);
    });

    test('returns null for empty bytes', () {
      expect(BodyDecodeService.decode(Uint8List(0), null), isNull);
    });

    test('returns UTF-8 string for text content', () {
      final bytes = Uint8List.fromList(utf8.encode('hello world'));
      expect(
        BodyDecodeService.decode(bytes, 'application/json'),
        'hello world',
      );
    });

    test('returns binary placeholder for image content type', () {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF]);
      final result = BodyDecodeService.decode(bytes, 'image/jpeg');
      expect(result, '\x00[binary: 3 bytes]');
    });

    test('returns binary placeholder when bytes fail UTF-8 decode', () {
      final bytes = Uint8List.fromList([0xFF, 0xFE]);
      final result = BodyDecodeService.decode(bytes, 'text/plain');
      expect(result, startsWith('\x00[binary:'));
    });
  });

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
      expect(result.length, 3);
    });
  });

  group('BodyDecodeService.tryUtf8', () {
    test('decodes valid UTF-8', () {
      final bytes = Uint8List.fromList(utf8.encode('hello'));
      expect(BodyDecodeService.tryUtf8(bytes), 'hello');
    });

    test('returns binary placeholder for invalid UTF-8', () {
      final bytes = Uint8List.fromList([0xFF, 0xFE]);
      expect(BodyDecodeService.tryUtf8(bytes), '\x00[binary: 2 bytes]');
    });
  });

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
      final (req, res, truncated) = BodyDecodeService.unpackToText(
        Uint8List.fromList([1, 2, 3]),
      );
      expect(req, isNull);
      expect(res, isNull);
      expect(truncated, isFalse);
    });

    test('decodes clean packed format without trailing flag byte', () {
      final packed = _packClean('{"id":1}', '{"ok":true}');
      final (req, res, truncated) = BodyDecodeService.unpackToText(packed);
      expect(req, '{"id":1}');
      expect(res, '{"ok":true}');
      expect(truncated, isFalse);
    });
  });

  group('BodyDecodeService.unpackToBytes', () {
    test('decodes packed req/res bodies to bytes', () {
      final reqText = '{"id":1}';
      final resText = '{"ok":true}';
      final packed = _packBodies(reqText, resText);
      final (reqBytes, resBytes, truncated) = BodyDecodeService.unpackToBytes(
        packed,
      );
      expect(utf8.decode(reqBytes!), reqText);
      expect(utf8.decode(resBytes!), resText);
      expect(truncated, isFalse);
    });

    test('decodes clean packed format without trailing flag byte', () {
      final reqText = '{"id":1}';
      final resText = '{"ok":true}';
      final packed = _packClean(reqText, resText);
      final (reqBytes, resBytes, truncated) = BodyDecodeService.unpackToBytes(
        packed,
      );
      expect(utf8.decode(reqBytes!), reqText);
      expect(utf8.decode(resBytes!), resText);
      expect(truncated, isFalse);
    });

    test('returns (null, null, false) for malformed raw bytes', () {
      final (req, res, truncated) = BodyDecodeService.unpackToBytes(
        Uint8List.fromList([0xFF]),
      );
      expect(req, isNull);
      expect(res, isNull);
      expect(truncated, isFalse);
    });
  });
}

Uint8List _packClean(String? req, String? res) {
  final reqBytes = req == null ? null : Uint8List.fromList(utf8.encode(req));
  final resBytes = res == null ? null : Uint8List.fromList(utf8.encode(res));
  final total = 4 + (reqBytes?.length ?? 0) + 4 + (resBytes?.length ?? 0);
  final out = Uint8List(total);
  final data = ByteData.sublistView(out);
  var offset = 0;

  void writePart(Uint8List? part) {
    if (part == null) {
      data.setUint32(offset, 0xFFFFFFFF, Endian.big);
      offset += 4;
      return;
    }
    data.setUint32(offset, part.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + part.length, part);
    offset += part.length;
  }

  writePart(reqBytes);
  writePart(resBytes);
  return out;
}

/// Builds a packed body record in the format that BodyDecodeService expects.
Uint8List _packBodies(String req, String res, {bool truncated = false}) {
  return _packRaw(utf8.encode(req), utf8.encode(res), truncated: truncated);
}

Uint8List _packBodiesPartial({
  String? req,
  String? res,
  bool truncated = false,
}) {
  return _packRaw(
    req == null ? null : utf8.encode(req),
    res == null ? null : utf8.encode(res),
    truncated: truncated,
  );
}

Uint8List _packRaw(List<int>? req, List<int>? res, {bool truncated = false}) {
  final reqBytes = req == null ? null : Uint8List.fromList(req);
  final resBytes = res == null ? null : Uint8List.fromList(res);
  final total = 4 + (reqBytes?.length ?? 0) + 4 + (resBytes?.length ?? 0) + 1;
  final out = Uint8List(total);
  final data = ByteData.sublistView(out);
  var offset = 0;

  void writePart(Uint8List? part) {
    if (part == null) {
      data.setUint32(offset, 0xFFFFFFFF, Endian.big);
      offset += 4;
      return;
    }
    data.setUint32(offset, part.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + part.length, part);
    offset += part.length;
  }

  writePart(reqBytes);
  writePart(resBytes);
  out[offset] = truncated ? 1 : 0;
  return out;
}
