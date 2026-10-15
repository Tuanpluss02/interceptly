import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../model/body_location.dart';
import '../model/body_truncation.dart';
import '../model/index_entry.dart';
import '../model/request_record.dart';
import 'body_decode_service.dart';
import 'body_store.dart';
import 'memory_index.dart';

/// Loads request and response details from memory or disk storage.
@internal
class DetailLoader {
  /// Creates a detail loader with index access and dynamic path/preview providers.
  DetailLoader({
    required MemoryIndex memoryIndex,
    required String? Function() tempFilePathProvider,
    required int Function() maxUiPreviewBytesProvider,
  })  : _memoryIndex = memoryIndex,
        _tempFilePathProvider = tempFilePathProvider,
        _maxUiPreviewBytesProvider = maxUiPreviewBytesProvider;

  final MemoryIndex _memoryIndex;
  final String? Function() _tempFilePathProvider;
  final int Function() _maxUiPreviewBytesProvider;

  /// Loads request details for the given [id].
  Future<RequestRecord> loadDetailById(String id) async {
    final entry = _memoryIndex.byId(id);
    if (entry == null) {
      throw ArgumentError.value(id, 'id', 'No entry found with id');
    }
    return loadDetailByEntry(entry);
  }

  /// Loads request details for the given index [entry].
  Future<RequestRecord> loadDetailByEntry(IndexEntry entry) async {
    String? reqPreview;
    String? resPreview;
    Uint8List? reqBytes;
    Uint8List? resBytes;
    var reqStorage = entry.requestTruncation;
    var resStorage = entry.responseTruncation;

    if (entry.bodyLocation == BodyLocation.memory) {
      reqBytes = entry.inlineRequestBody;
      resBytes = entry.inlineResponseBody;
    } else {
      final offset = entry.fileOffset;
      final length = entry.fileLength;
      final filePath = _tempFilePathProvider();

      if (offset != null && length != null && filePath != null) {
        try {
          final raw = await BodyStore.readBytes(filePath, offset, length);
          if (raw.length < length) {
            throw const FileSystemException('Truncated body read');
          }
          final decoded = raw.length > BodyDecodeService.computeThreshold
              ? await compute(BodyDecodeService.unpackToBytes, raw)
              : BodyDecodeService.unpackToBytes(raw);
          if (decoded.$1 == null && decoded.$2 == null && length > 9) {
            reqPreview = BodyDecodeService.unavailablePlaceholder;
            resPreview = BodyDecodeService.unavailablePlaceholder;
          } else {
            reqBytes = decoded.$1;
            resBytes = decoded.$2;
          }
        } catch (_) {
          reqPreview = BodyDecodeService.unavailablePlaceholder;
          resPreview = BodyDecodeService.unavailablePlaceholder;
        }
      } else {
        reqPreview = BodyDecodeService.unavailablePlaceholder;
        resPreview = BodyDecodeService.unavailablePlaceholder;
      }
    }

    final maxUi = _maxUiPreviewBytesProvider();

    if (reqPreview == null && reqBytes != null) {
      final reqSlice = limitForPreview(reqBytes, maxUi);
      reqStorage =
          applyPreviewStage(reqStorage, reqBytes.length, reqSlice.length);
      reqPreview = await BodyDecodeService.decodeAsync(
        reqSlice,
        entry.requestContentType,
      );
    }

    if (resPreview == null && resBytes != null) {
      final resSlice = limitForPreview(resBytes, maxUi);
      resStorage =
          applyPreviewStage(resStorage, resBytes.length, resSlice.length);
      resPreview = await BodyDecodeService.decodeAsync(
        resSlice,
        entry.responseContentType,
      );
    }

    return RequestRecord(
      id: entry.id,
      method: entry.method,
      url: entry.url,
      statusCode: entry.statusCode,
      durationMs: entry.durationMs,
      requestSizeBytes: entry.requestSizeBytes,
      responseSizeBytes: entry.responseSizeBytes,
      timestamp: entry.timestamp,
      requestHeaders: entry.requestHeaders,
      responseHeaders: entry.responseHeaders,
      requestContentType: entry.requestContentType,
      responseContentType: entry.responseContentType,
      requestBodyPreview: reqPreview,
      responseBodyPreview: resPreview,
      requestBodyBytes: reqBytes,
      responseBodyBytes: resBytes,
      requestTruncation: reqStorage,
      responseTruncation: resStorage,
      errorType: entry.errorType,
      errorMessage: entry.errorMessage,
    );
  }

  /// Truncates [bytes] to [maxUi] bytes for UI presentation.
  static Uint8List limitForPreview(Uint8List bytes, int maxUi) =>
      maxUi > 0 && bytes.length > maxUi ? bytes.sublist(0, maxUi) : bytes;

  /// Marks [truncation] as storage-cut preserving recorded original size.
  static BodyTruncation markStorageCut(BodyTruncation truncation, int kept) {
    return BodyTruncation(
      originalBytes: truncation.originalBytes,
      retainedBytes: kept,
      stage: TruncationStage.storage,
    );
  }

  /// Merges storage and preview truncation verdicts.
  static BodyTruncation applyPreviewStage(
    BodyTruncation truncation,
    int availableBytes,
    int previewBytes,
  ) {
    final previewCut = previewBytes < availableBytes;
    final storageCut = truncation.stage == TruncationStage.storage ||
        truncation.stage == TruncationStage.storageAndPreview;
    if (!previewCut) {
      return truncation;
    }
    return BodyTruncation(
      originalBytes: truncation.originalBytes,
      retainedBytes: previewBytes,
      stage: storageCut
          ? TruncationStage.storageAndPreview
          : TruncationStage.preview,
    );
  }
}
