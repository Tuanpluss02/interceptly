import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/realtime_frame.dart';
import 'ring_buffer.dart';

/// Stores and buffers realtime frames per session ID, throttling UI notifications.
@internal
class RealtimeStore {
  /// Creates a realtime frame store with capacity [maxFramesPerSession] and
  /// batch callback [onThrottledBatch].
  RealtimeStore({
    required int maxFramesPerSession,
    required VoidCallback onThrottledBatch,
  })  : _maxFramesPerSession = maxFramesPerSession,
        _onThrottledBatch = onThrottledBatch;

  int _maxFramesPerSession;
  final VoidCallback _onThrottledBatch;
  final Map<String, RingBuffer<RealtimeFrame>> _realtimeFramesBySession = {};
  Timer? _throttleTimer;
  bool _hasPendingNotification = false;
  bool _isDisposed = false;

  /// Appends [frame] to the buffer for its session and schedules a throttled notification.
  void recordFrame(RealtimeFrame frame) {
    if (_isDisposed) return;

    final buffer = _realtimeFramesBySession.putIfAbsent(
      frame.sessionId,
      () => RingBuffer<RealtimeFrame>(capacity: _maxFramesPerSession),
    );
    buffer.add(frame);

    _scheduleNotification();
  }

  void _scheduleNotification() {
    if (_isDisposed) return;
    _hasPendingNotification = true;
    _throttleTimer ??= Timer(const Duration(milliseconds: 100), () {
      _throttleTimer = null;
      if (_hasPendingNotification && !_isDisposed) {
        _hasPendingNotification = false;
        _onThrottledBatch();
      }
    });
  }

  /// Returns captured frames for [sessionId] in FIFO order.
  List<RealtimeFrame> getFrames(String sessionId) {
    if (_isDisposed) return const <RealtimeFrame>[];
    final buffer = _realtimeFramesBySession[sessionId];
    if (buffer == null || buffer.isEmpty) {
      return const <RealtimeFrame>[];
    }
    return buffer.toList();
  }

  /// Updates maximum capacity for all current and future session buffers.
  void updateMaxFramesPerSession(int maxFrames) {
    _maxFramesPerSession = maxFrames;
    for (final buffer in _realtimeFramesBySession.values) {
      buffer.updateCapacity(maxFrames);
    }
  }

  /// Clears all stored frames and cancels any scheduled batch notification.
  void clear() {
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _hasPendingNotification = false;
    _realtimeFramesBySession.clear();
  }

  /// Disposes the store, canceling background timers and clearing buffers.
  void dispose() {
    _isDisposed = true;
    clear();
  }
}
