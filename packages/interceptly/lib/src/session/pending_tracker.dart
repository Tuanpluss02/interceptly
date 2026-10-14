import 'dart:async';

import 'package:flutter/foundation.dart';

import '../capture/capture_guard.dart';
import '../model/body_location.dart';
import '../model/body_truncation.dart';
import '../model/index_entry.dart';
import '../model/interceptly_settings.dart';
import 'body_decode_service.dart';
import 'capture_pipeline.dart';
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
    final sanitizedHeaders = CaptureGuard.redactHeaders(
      requestHeaders,
      settings.normalizedRedactedHeaders,
    );
    final sanitizedUrl = CaptureGuard.sanitizeUrl(
      url,
      settings.normalizedRedactedQueryParams,
    );
    final redactedRequestBody = CapturePipeline.redactInlineBytes(
      requestBodyBytes,
      settings.bodyRedactor,
    );
    final inlineRequestBody = BodyDecodeService.truncate(
      redactedRequestBody,
      settings.maxBodyBytes,
      settings.previewTruncationBytes,
    );
    final requestSize = redactedRequestBody?.length ?? 0;
    final requestTruncation = pendingRequestTruncation(
      originalBytes: requestSize,
      inlineBytes: inlineRequestBody?.length ?? 0,
    );

    _memoryIndex.add(
      IndexEntry(
        id: id,
        method: method,
        url: sanitizedUrl,
        statusCode: 0,
        durationMs: 0,
        requestSizeBytes: requestSize,
        responseSizeBytes: 0,
        timestamp: timestamp,
        hasError: false,
        bodyLocation: BodyLocation.memory,
        inlineRequestBody: inlineRequestBody,
        inlineResponseBody: null,
        requestHeaders: sanitizedHeaders,
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
      IndexEntry(
        id: current.id,
        method: current.method,
        url: current.url,
        statusCode: closeCode,
        durationMs:
            DateTime.now().difference(current.timestamp).inMilliseconds,
        requestSizeBytes: current.requestSizeBytes,
        responseSizeBytes: current.responseSizeBytes,
        timestamp: current.timestamp,
        hasError: closeCode > 1000 && closeCode != 1005,
        bodyLocation: current.bodyLocation,
        inlineRequestBody: current.inlineRequestBody,
        inlineResponseBody: current.inlineResponseBody,
        requestHeaders: current.requestHeaders,
        responseHeaders: current.responseHeaders,
        requestContentType: current.requestContentType,
        responseContentType: current.responseContentType,
        errorType: current.errorType,
        errorMessage: closeReason ?? current.errorMessage,
        requestTruncation: current.requestTruncation,
        responseTruncation: current.responseTruncation,
        fileOffset: current.fileOffset,
        fileLength: current.fileLength,
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

      final timedOutEntry = IndexEntry(
        id: current.id,
        method: current.method,
        url: current.url,
        statusCode: 0,
        durationMs: current.durationMs,
        requestSizeBytes: current.requestSizeBytes,
        responseSizeBytes: current.responseSizeBytes,
        timestamp: current.timestamp,
        hasError: true,
        bodyLocation: current.bodyLocation,
        inlineRequestBody: current.inlineRequestBody,
        inlineResponseBody: current.inlineResponseBody,
        requestHeaders: current.requestHeaders,
        responseHeaders: current.responseHeaders,
        requestContentType: current.requestContentType,
        responseContentType: current.responseContentType,
        errorType: 'TimeoutException',
        errorMessage:
            'Request timed out while waiting for response or terminal error.',
        requestTruncation: current.requestTruncation,
        responseTruncation: current.responseTruncation,
        fileOffset: current.fileOffset,
        fileLength: current.fileLength,
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
