import 'dart:convert';
import 'dart:typed_data';

import '../model/realtime_frame.dart';
import 'body_bytes.dart';

/// The result of normalizing a raw incoming or outgoing frame payload in a single pass.
class NormalizedFrame {
  /// The resolved frame protocol type (text, binary, etc.).
  final FrameType type;

  /// The processed payload: either a [String] for text frames, or a [Uint8List] for binary frames.
  final dynamic payload;

  /// The original un-truncated payload size in bytes.
  final int originalSizeBytes;

  /// A short, safe preview string (<= 128 characters) suitable for list display without layout strain.
  final String shortPreview;

  /// Whether this frame exceeds the offload threshold and should be streamed to disk.
  final bool shouldOffload;

  /// Pre-encoded UTF-8 or raw bytes prepared for zero-re-encoding disk offload.
  final Uint8List? preEncodedBytes;

  const NormalizedFrame({
    required this.type,
    required this.payload,
    required this.originalSizeBytes,
    required this.shortPreview,
    required this.shouldOffload,
    this.preEncodedBytes,
  });
}

/// Utility for single-pass, zero-allocation frame normalization.
///
/// Determines frame type, computes true byte lengths without redundant UTF-8 allocations,
/// avoids copying [Uint8List] buffers, generates short previews, and decides offload eligibility.
class FrameNormalizer {
  /// Normalizes [raw] in a single pass.
  ///
  /// - Computes [originalSizeBytes] with 0 heap byte allocations for UTF-8 text via [utf8ByteLength].
  /// - Avoids cloning [Uint8List] / [ByteData] buffers (uses [Uint8List.sublistView] when truncating).
  /// - Caps generic [List<int>] windows with take before copying to avoid full allocation.
  /// - Generates a safe Unicode [shortPreview] (<= 128 chars).
  /// - Flags [shouldOffload] when [originalSizeBytes] >= [offloadThreshold] and [offloadThreshold] > 0.
  /// - Pre-encodes [preEncodedBytes] once when [shouldOffload] is true, eliminating downstream re-encoding.
  static NormalizedFrame normalize(
    dynamic raw, {
    required int offloadThreshold,
    required int maxBodyBytes,
    FrameType? explicitType,
  }) {
    FrameType type;
    dynamic payload;
    int originalSize;
    Uint8List? preEncodedBytes;
    bool shouldOffload;

    if (raw is Uint8List) {
      type = explicitType ?? FrameType.binary;
      originalSize = raw.lengthInBytes;
      shouldOffload = offloadThreshold > 0 && originalSize >= offloadThreshold;
      final capped = (maxBodyBytes > 0 && originalSize > maxBodyBytes)
          ? raw.sublist(0, maxBodyBytes)
          : raw;
      payload = capped;
      if (shouldOffload) {
        preEncodedBytes = capped;
      }
    } else if (raw is ByteData) {
      type = explicitType ?? FrameType.binary;
      final bytes =
          raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
      originalSize = bytes.lengthInBytes;
      shouldOffload = offloadThreshold > 0 && originalSize >= offloadThreshold;
      final capped = (maxBodyBytes > 0 && originalSize > maxBodyBytes)
          ? bytes.sublist(0, maxBodyBytes)
          : bytes;
      payload = capped;
      if (shouldOffload) {
        preEncodedBytes = capped;
      }
    } else if (raw is List<int> && explicitType != FrameType.text) {
      type = explicitType ?? FrameType.binary;
      originalSize = raw.length;
      final Uint8List bytes;
      if (raw is Uint8List) {
        bytes = raw;
      } else if (maxBodyBytes > 0 && originalSize > maxBodyBytes) {
        bytes = Uint8List.fromList(raw.take(maxBodyBytes).toList());
      } else {
        bytes = Uint8List.fromList(raw);
      }
      shouldOffload = offloadThreshold > 0 && originalSize >= offloadThreshold;
      final capped = (maxBodyBytes > 0 &&
              originalSize > maxBodyBytes &&
              bytes.length > maxBodyBytes)
          ? bytes.sublist(0, maxBodyBytes)
          : bytes;
      payload = capped;
      if (shouldOffload) {
        preEncodedBytes = capped;
      }
    } else if (raw is String) {
      type = explicitType ?? FrameType.text;
      originalSize = utf8ByteLength(raw);
      shouldOffload = offloadThreshold > 0 && originalSize >= offloadThreshold;
      final cappedText = (maxBodyBytes > 0 && originalSize > maxBodyBytes)
          ? truncateUtf8(raw, maxBodyBytes)
          : raw;
      payload = cappedText;
      if (shouldOffload) {
        preEncodedBytes = Uint8List.fromList(utf8.encode(cappedText));
      }
    } else if (raw is Map || raw is List) {
      type = explicitType ?? FrameType.text;
      String text;
      try {
        text = jsonEncode(raw);
      } catch (_) {
        text = raw.toString();
      }
      originalSize = utf8ByteLength(text);
      shouldOffload = offloadThreshold > 0 && originalSize >= offloadThreshold;
      final cappedText = (maxBodyBytes > 0 && originalSize > maxBodyBytes)
          ? truncateUtf8(text, maxBodyBytes)
          : text;
      payload = cappedText;
      if (shouldOffload) {
        preEncodedBytes = Uint8List.fromList(utf8.encode(cappedText));
      }
    } else if (raw == null) {
      type = explicitType ?? FrameType.text;
      originalSize = 0;
      shouldOffload = false;
      payload = '';
    } else {
      type = explicitType ?? FrameType.text;
      final text = raw.toString();
      if (offloadThreshold > 0 && text.length >= offloadThreshold) {
        final bytes = Uint8List.fromList(utf8.encode(text));
        originalSize = bytes.lengthInBytes;
        shouldOffload = true;
        preEncodedBytes = bytes;
      } else {
        originalSize = utf8ByteLength(text);
        shouldOffload =
            offloadThreshold > 0 && originalSize >= offloadThreshold;
        if (shouldOffload) {
          preEncodedBytes = Uint8List.fromList(utf8.encode(text));
        }
      }
      if (maxBodyBytes > 0 && originalSize > maxBodyBytes) {
        payload = truncateUtf8(text, maxBodyBytes);
      } else {
        payload = text;
      }
    }

    final shortPreview = RealtimeFrame.extractShortPreview(payload, type);

    return NormalizedFrame(
      type: type,
      payload: payload,
      originalSizeBytes: originalSize,
      shortPreview: shortPreview,
      shouldOffload: shouldOffload,
      preEncodedBytes: preEncodedBytes,
    );
  }
}
