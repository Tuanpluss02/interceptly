import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/body_truncation.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/session/detail_loader.dart';
import 'package:interceptly/src/session/memory_index.dart';

/// Helper to pack bodies with the legacy trailing truncated byte.
Uint8List _packLegacy(Uint8List? req, Uint8List? res,
    {required bool isTruncated}) {
  final total = 4 + (req?.length ?? 0) + 4 + (res?.length ?? 0) + 1;
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

  writePart(req);
  writePart(res);
  out[offset] = isTruncated ? 1 : 0;
  return out;
}

void main() {
  late Directory tempDir;
  late File tempFile;
  late MemoryIndex memoryIndex;
  late DetailLoader detailLoader;

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('per_side_truncation_test_');
    tempFile = File('${tempDir.path}/body_store.bin');
    memoryIndex = MemoryIndex(maxEntries: 100);
    detailLoader = DetailLoader(
      memoryIndex: memoryIndex,
      tempFilePathProvider: () => tempFile.path,
      maxUiPreviewBytesProvider: () => 50000,
    );
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Per-Side Truncation Isolation', () {
    test(
        'detail loader does not mark request as storage cut when only response was truncated',
        () async {
      final reqBytes = Uint8List.fromList(utf8.encode(''));
      final resBytes = Uint8List.fromList(utf8.encode('{"partial": true}'));

      // Legacy packed format with trailing flag = 1 (indicating some truncation)
      final packed = _packLegacy(reqBytes, resBytes, isTruncated: true);
      await tempFile.writeAsBytes(packed);

      final entry = IndexEntry(
        id: 'entry-1',
        method: 'POST',
        url: 'https://api.com/upload',
        statusCode: 200,
        durationMs: 15,
        requestSizeBytes: 0,
        responseSizeBytes: 1000,
        timestamp: DateTime(2026, 10, 14),
        hasError: false,
        bodyLocation: BodyLocation.file,
        fileOffset: 0,
        fileLength: packed.length,
        requestTruncation: const BodyTruncation.complete(0),
        responseTruncation: const BodyTruncation(
          originalBytes: 1000,
          retainedBytes: 17,
          stage: TruncationStage.storage,
        ),
      );

      final record = await detailLoader.loadDetailByEntry(entry);

      // DetailLoader should trust entry.requestTruncation and NOT override it
      expect(record.requestTruncation.hasDataLoss, isFalse);
      expect(record.requestTruncation.stage, equals(TruncationStage.none));

      // Response truncation remains storage-cut
      expect(record.responseTruncation.hasDataLoss, isTrue);
      expect(record.responseTruncation.stage, equals(TruncationStage.storage));
      expect(record.responseTruncation.originalBytes, equals(1000));
    });

    test(
        'detail loader does not mark response as storage cut when only request was truncated',
        () async {
      final reqBytes = Uint8List.fromList(utf8.encode('partial_request'));
      final resBytes = Uint8List.fromList(utf8.encode('{"status":"ok"}'));

      final packed = _packLegacy(reqBytes, resBytes, isTruncated: true);
      await tempFile.writeAsBytes(packed);

      final entry = IndexEntry(
        id: 'entry-2',
        method: 'POST',
        url: 'https://api.com/submit',
        statusCode: 200,
        durationMs: 20,
        requestSizeBytes: 500,
        responseSizeBytes: 15,
        timestamp: DateTime(2026, 10, 14),
        hasError: false,
        bodyLocation: BodyLocation.file,
        fileOffset: 0,
        fileLength: packed.length,
        requestTruncation: const BodyTruncation(
          originalBytes: 500,
          retainedBytes: 15,
          stage: TruncationStage.storage,
        ),
        responseTruncation: const BodyTruncation.complete(15),
      );

      final record = await detailLoader.loadDetailByEntry(entry);

      // Request was truncated in storage
      expect(record.requestTruncation.hasDataLoss, isTrue);
      expect(record.requestTruncation.stage, equals(TruncationStage.storage));

      // Response was NOT truncated in storage
      expect(record.responseTruncation.hasDataLoss, isFalse);
      expect(record.responseTruncation.stage, equals(TruncationStage.none));
    });
  });
}
