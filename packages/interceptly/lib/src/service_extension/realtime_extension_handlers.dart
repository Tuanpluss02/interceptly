import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '../engine/interceptly_engine.dart';
import '../model/realtime_frame.dart';
import 'service_extension_exception.dart';

/// Handlers for WebSocket and Realtime traffic inspection service extensions.
abstract final class RealtimeExtensionHandlers {
  /// Handles `ext.interceptly.listRealtimeFrames`.
  ///
  /// Query parameters:
  /// - `session_id`: the realtime connection ID
  /// - `direction`: 'all' | 'incoming' | 'outgoing'
  /// - `type`: 'all' | 'text' | 'binary' | 'ping' | 'pong' | 'close' | 'ack'
  /// - `since_id`: cursor pagination (returns only frames strictly after [since_id])
  /// - `limit`: maximum number of frames to return (default 50, max 200)
  static Future<Map<String, dynamic>> handleListRealtimeFrames({
    required InterceptlyEngine? engine,
    required Map<String, String> parameters,
    bool isEnabled = true,
  }) async {
    checkServiceExtensionEnabled(isEnabled);

    final sessionId = parameters['session_id'];
    if (sessionId == null || sessionId.trim().isEmpty) {
      throw const ServiceExtensionException(
        developer.ServiceExtensionResponse.invalidParams,
        'Missing required parameter: session_id',
      );
    }

    if (engine == null) {
      return {
        'sessionId': sessionId,
        'total': 0,
        'count': 0,
        'frames': const <Map<String, dynamic>>[],
      };
    }

    final allFrames = engine.getRealtimeFrames(sessionId);
    final directionFilter = (parameters['direction'] ?? 'all').toLowerCase();
    final FrameDirection? targetDirection = switch (directionFilter) {
      'incoming' ||
      'inbound' ||
      'received' ||
      'receive' ||
      'in' =>
        FrameDirection.incoming,
      'outgoing' ||
      'outbound' ||
      'sent' ||
      'send' ||
      'out' =>
        FrameDirection.outgoing,
      _ => null,
    };
    final typeFilter = (parameters['type'] ?? 'all').toLowerCase();
    final sinceId = parameters['since_id'];
    final limit =
        int.tryParse(parameters['limit'] ?? '50')?.clamp(1, 200) ?? 50;

    var filtered = allFrames.where((f) {
      if (targetDirection != null && f.direction != targetDirection) {
        return false;
      }
      if (typeFilter != 'all' && f.type.name != typeFilter) {
        return false;
      }
      return true;
    }).toList();

    if (sinceId != null && sinceId.isNotEmpty) {
      final idx = filtered.indexWhere((f) => f.id == sinceId);
      if (idx != -1) {
        filtered = filtered.sublist(idx + 1);
      } else {
        filtered = <RealtimeFrame>[];
      }
    }

    final paged = filtered
        .take(limit)
        .map((f) => {
              'id': f.id,
              'sessionId': f.sessionId,
              'direction': f.direction.name,
              'type': f.type.name,
              'eventName': f.eventName,
              'payloadSizeBytes': f.payloadSizeBytes,
              'shortPreview': f.shortPreview,
              'timestamp': f.timestamp.toIso8601String(),
            })
        .toList();

    return {
      'sessionId': sessionId,
      'total': allFrames.length,
      'count': paged.length,
      'frames': paged,
    };
  }

  /// Handles `ext.interceptly.getRealtimeFrameDetail`.
  ///
  /// Query parameters:
  /// - `session_id`: the connection session ID
  /// - `frame_id`: the unique frame ID
  /// - `offset`: character offset for reading large payloads (default 0)
  /// - `max_chars`: maximum characters to return before truncation (default 4000)
  static Future<Map<String, dynamic>> handleGetRealtimeFrameDetail({
    required InterceptlyEngine? engine,
    required Map<String, String> parameters,
    bool isEnabled = true,
  }) async {
    checkServiceExtensionEnabled(isEnabled);

    final sessionId = parameters['session_id'];
    final frameId = parameters['frame_id'];
    if (sessionId == null || frameId == null) {
      throw const ServiceExtensionException(
        developer.ServiceExtensionResponse.invalidParams,
        'Missing required parameters: session_id and frame_id',
      );
    }

    if (engine == null) {
      throw const ServiceExtensionException(
        developer.ServiceExtensionResponse.extensionError,
        'Interceptly engine is not available',
      );
    }

    final frames = engine.getRealtimeFrames(sessionId);
    final frame = frames.cast<RealtimeFrame?>().firstWhere(
          (f) => f?.id == frameId,
          orElse: () => null,
        );

    if (frame == null) {
      throw ServiceExtensionException(
        developer.ServiceExtensionResponse.invalidParams,
        'Frame not found: $frameId in session $sessionId',
      );
    }

    final dynamic rawPayload = await engine.loadRealtimePayload(frame);
    String payloadStr;
    bool isBinary = false;

    if (rawPayload is String) {
      payloadStr = rawPayload;
    } else if (rawPayload is Uint8List) {
      isBinary = true;
      payloadStr = base64Encode(rawPayload);
    } else {
      payloadStr = frame.shortPreview;
    }

    final offset = int.tryParse(parameters['offset'] ?? '0') ?? 0;
    final maxChars = int.tryParse(parameters['max_chars'] ?? '4000') ?? 4000;

    final totalChars = payloadStr.length;
    final safeOffset = offset.clamp(0, totalChars);
    final end = (safeOffset + maxChars).clamp(safeOffset, totalChars);
    final slice = payloadStr.substring(safeOffset, end);
    final isTruncated = end < totalChars;
    final remainingChars = totalChars - end;

    return {
      'id': frame.id,
      'sessionId': frame.sessionId,
      'direction': frame.direction.name,
      'type': frame.type.name,
      'eventName': frame.eventName,
      'isBinary': isBinary,
      'payloadSizeBytes': frame.payloadSizeBytes,
      'timestamp': frame.timestamp.toIso8601String(),
      'payload': slice,
      'isTruncated': isTruncated,
      'totalChars': totalChars,
      'offset': safeOffset,
      'remainingChars': remainingChars,
    };
  }
}
