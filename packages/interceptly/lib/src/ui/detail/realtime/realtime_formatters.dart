import 'dart:convert';
import 'dart:typed_data';

import 'package:interceptly/src/model/realtime_frame.dart';

/// Formats a [DateTime] into `HH:mm:ss.SSS` for realtime log rows.
String formatFrameTimestamp(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  final ms = dt.millisecond.toString().padLeft(3, '0');
  return '$h:$m:$s.$ms';
}

/// Human-readable label for a given [FrameType].
String frameTypeLabel(FrameType type) {
  switch (type) {
    case FrameType.text:
      return 'Text';
    case FrameType.binary:
      return 'Binary';
    case FrameType.ping:
      return 'Ping';
    case FrameType.pong:
      return 'Pong';
    case FrameType.close:
      return 'Close';
    case FrameType.ack:
      return 'Ack';
  }
}

/// Formats a binary payload preview with byte length and hex sample.
String formatBinaryPreview(Uint8List bytes) {
  if (bytes.isEmpty) return '[empty binary]';
  final sample =
      bytes.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  final suffix = bytes.length > 16 ? '...' : '';
  return '[binary: ${bytes.length} bytes] $sample$suffix';
}

/// Resolves a displayable string for a given [frame] payload.
String getFramePayloadString(RealtimeFrame frame) {
  if (frame.textPayload != null) {
    return frame.textPayload!;
  }
  if (frame.binaryPayload != null) {
    return formatBinaryPreview(frame.binaryPayload!);
  }
  if (frame.shortPreview.isNotEmpty) {
    return frame.shortPreview;
  }
  return frame.type.name.toUpperCase();
}

/// Attempts to parse JSON from [frame] text payload using a per-session [cache].
dynamic tryParseJsonPayload(
  RealtimeFrame frame,
  Map<String, dynamic> cache,
) {
  final text = frame.textPayload;
  if (text == null || text.trim().isEmpty) return null;
  if (cache.containsKey(frame.id)) {
    return cache[frame.id];
  }
  try {
    final parsed = jsonDecode(text);
    cache[frame.id] = parsed;
    return parsed;
  } catch (_) {
    cache[frame.id] = null;
    return null;
  }
}
