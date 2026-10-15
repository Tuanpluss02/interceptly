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

  const NormalizedFrame({
    required this.type,
    required this.payload,
    required this.originalSizeBytes,
    required this.shortPreview,
    required this.shouldOffload,
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
  /// - Generates a safe Unicode [shortPreview] (<= 128 chars).
  /// - Flags [shouldOffload] when [originalSizeBytes] >= [offloadThreshold] and [offloadThreshold] > 0.
  static NormalizedFrame normalize(
    dynamic raw, {
    required int offloadThreshold,
    required int maxBodyBytes,
    FrameType? explicitType,
  }) {
    FrameType type;
    dynamic payload;
    int originalSize;

    if (raw is Uint8List) {
      type = explicitType ?? FrameType.binary;
      originalSize = raw.lengthInBytes;
      if (maxBodyBytes > 0 && originalSize > maxBodyBytes) {
        payload = Uint8List.sublistView(raw, 0, maxBodyBytes);
      } else {
        payload = raw;
      }
    } else if (raw is ByteData) {
      type = explicitType ?? FrameType.binary;
      final bytes = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
      originalSize = bytes.lengthInBytes;
      if (maxBodyBytes > 0 && originalSize > maxBodyBytes) {
        payload = Uint8List.sublistView(bytes, 0, maxBodyBytes);
      } else {
        payload = bytes;
      }
    } else if (raw is List<int> && explicitType != FrameType.text) {
      type = explicitType ?? FrameType.binary;
      originalSize = raw.length;
      if (maxBodyBytes > 0 && originalSize > maxBodyBytes) {
        payload = Uint8List.fromList(raw.sublist(0, maxBodyBytes));
      } else {
        payload = Uint8List.fromList(raw);
      }
    } else if (raw is String) {
      type = explicitType ?? FrameType.text;
      originalSize = utf8ByteLength(raw);
      if (maxBodyBytes > 0 && originalSize > maxBodyBytes) {
        payload = truncateUtf8(raw, maxBodyBytes);
      } else {
        payload = raw;
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
      if (maxBodyBytes > 0 && originalSize > maxBodyBytes) {
        payload = truncateUtf8(text, maxBodyBytes);
      } else {
        payload = text;
      }
    } else if (raw == null) {
      type = explicitType ?? FrameType.text;
      originalSize = 0;
      payload = '';
    } else {
      type = explicitType ?? FrameType.text;
      final text = raw.toString();
      originalSize = utf8ByteLength(text);
      if (maxBodyBytes > 0 && originalSize > maxBodyBytes) {
        payload = truncateUtf8(text, maxBodyBytes);
      } else {
        payload = text;
      }
    }

    final shouldOffload =
        offloadThreshold > 0 && originalSize >= offloadThreshold;
    final shortPreview = RealtimeFrame.extractShortPreview(payload, type);

    return NormalizedFrame(
      type: type,
      payload: payload,
      originalSizeBytes: originalSize,
      shortPreview: shortPreview,
      shouldOffload: shouldOffload,
    );
  }
}
