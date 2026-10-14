import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/body_location.dart';
import '../model/body_truncation.dart';
import '../model/index_entry.dart';
import '../model/interceptly_settings.dart';
import 'body_decode_service.dart';
import 'memory_index.dart';

/// Tracks pending request timers and handles timeout expiration or cancellation.
@internal
class PendingTracker {
  /// Creates a tracker for pending requests using [timeoutDuration].
  PendingTracker({
    required Duration timeoutDuration,
    required MemoryIndex memoryIndex,
    required void Function(IndexEntry timedOutEntry) onTimeout,
  })  : _timeoutDuration = timeoutDuration,
        _memoryIndex = memoryIndex,
        _onTimeout = onTimeout;

  Duration _timeoutDuration;
  final MemoryIndex _memoryIndex;
  final void Function(IndexEntry timedOutEntry) _onTimeout;
  final Map<String, Timer> _pendingTimers = {};

  /// Updates the timeout duration applied to subsequent pending requests.
  void updateTimeout(Duration newTimeout) {
    _timeoutDuration = newTimeout;
  }

  /// Inserts a pending request entry into [MemoryIndex] and starts its timeout timer.
  void recordPending({
    required String id,
    required String method,
    required String url,
    required DateTime timestamp,
    Map<String, String> requestHeaders = const {},
    Uint8List? requestBodyBytes,
    String? requestContentType,
    required InterceptlySettings settings,
  }) {
    final inlineRequestBody = BodyDecodeService.truncate(
      requestBodyBytes,
      settings.maxBodyBytes,
      settings.previewTruncationBytes,
    );
    final requestSize = requestBodyBytes?.length ?? 0;
    final requestTruncation = pendingRequestTruncation(
      originalBytes: requestSize,
      inlineBytes: inlineRequestBody?.length ?? 0,
    );

    _memoryIndex.add(
      IndexEntry(
        id: id,
        method: method,
        url: url,
        statusCode: 0,
        durationMs: 0,
        requestSizeBytes: requestSize,
        responseSizeBytes: 0,
        timestamp: timestamp,
        hasError: false,
        bodyLocation: BodyLocation.memory,
        inlineRequestBody: inlineRequestBody,
        inlineResponseBody: null,
        requestHeaders: requestHeaders,
        responseHeaders: const {},
        requestContentType: requestContentType,
        responseContentType: null,
        errorType: null,
        errorMessage: null,
        requestTruncation: requestTruncation,
        responseTruncation: const BodyTruncation.complete(0),
        fileOffset: null,
        fileLength: null,
      ),
    );
    schedule(id);
  }

  /// Marks a pending realtime connection as closed with [closeCode] and [closeReason].
  void closeRealtimeConnection(
    String id, {
    int closeCode = 1000,
    String? closeReason,
  }) {
    cancel(id);
    final current = _memoryIndex.byId(id);
    if (current == null) return;

    _memoryIndex.add(
      current.copyWith(
        statusCode: closeCode,
        durationMs:
            DateTime.now().difference(current.timestamp).inMilliseconds,
        hasError: closeCode > 1000 && closeCode != 1005,
        errorMessage: closeReason ?? current.errorMessage,
      ),
    );
  }

  /// Schedules a timeout timer for pending request [id].
  void schedule(String id) {
    cancel(id);
    _pendingTimers[id] = Timer(_timeoutDuration, () {
      _pendingTimers.remove(id);

      final current = _memoryIndex.byId(id);
      if (current == null) return;
      if (current.statusCode != 0 || current.hasError) return;

      final timedOutEntry = current.copyWith(
        hasError: true,
        errorType: 'TimeoutException',
        errorMessage:
            'Request timed out while waiting for response or terminal error.',
      );

      _memoryIndex.add(timedOutEntry);
      _onTimeout(timedOutEntry);
    });
  }

  /// Cancels the timeout timer for request [id].
  void cancel(String id) {
    _pendingTimers.remove(id)?.cancel();
  }

  /// Cancels all active pending timers and clears the tracker state.
  void clear() {
    for (final timer in _pendingTimers.values) {
      timer.cancel();
    }
    _pendingTimers.clear();
  }

  /// Disposes the tracker and cancels all scheduled timers.
  void dispose() {
    clear();
  }

  /// Computes request truncation for preview storage on pending requests.
  static BodyTruncation pendingRequestTruncation({
    required int originalBytes,
    required int inlineBytes,
  }) {
    if (inlineBytes >= originalBytes) {
      return BodyTruncation.complete(originalBytes);
    }
    return BodyTruncation(
      originalBytes: originalBytes,
      retainedBytes: inlineBytes,
      stage: TruncationStage.preview,
    );
  }
}
