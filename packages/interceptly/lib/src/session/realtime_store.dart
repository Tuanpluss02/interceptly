import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../model/realtime_frame.dart';

/// A high-performance, dynamic circular buffer that grows on demand from a small
/// initial allocation up to [maxCapacity], and then operates as an O(1) ring buffer.
class DynamicCircularBuffer {
  /// Creates a dynamic circular buffer with [maxCapacity] and [initialCapacity].
  DynamicCircularBuffer({required int maxCapacity, int initialCapacity = 16})
      : _maxCapacity = maxCapacity,
        _capacity = initialCapacity.clamp(1, maxCapacity) {
    _buffer = List<RealtimeFrame?>.filled(_capacity, null);
  }

  int _maxCapacity;
  int _capacity;
  late List<RealtimeFrame?> _buffer;
  int _head = 0;
  int _count = 0;

  /// Current number of items in the buffer.
  int get count => _count;

  /// True if buffer has no elements.
  bool get isEmpty => _count == 0;

  /// True if buffer contains at least one element.
  bool get isNotEmpty => _count > 0;

  /// Current allocated capacity of the internal buffer.
  int get capacity => _capacity;

  /// Maximum allowed capacity before overwriting oldest items.
  int get maxCapacity => _maxCapacity;

  /// Appends [item] to the buffer.
  ///
  /// Expands capacity exponentially (up to [_maxCapacity]) when full.
  /// Once [_maxCapacity] is reached, overwrites the oldest element in O(1).
  void add(RealtimeFrame item) {
    if (_count < _capacity) {
      final index = (_head + _count) % _capacity;
      _buffer[index] = item;
      _count++;
      return;
    }

    if (_capacity < _maxCapacity) {
      _grow();
      final index = (_head + _count) % _capacity;
      _buffer[index] = item;
      _count++;
      return;
    }

    // Full at max capacity: overwrite head (oldest element)
    _buffer[_head] = item;
    _head = (_head + 1) % _capacity;
  }

  void _grow() {
    final newCapacity = (_capacity * 2).clamp(1, _maxCapacity);
    final newBuffer = List<RealtimeFrame?>.filled(newCapacity, null);
    for (var i = 0; i < _count; i++) {
      newBuffer[i] = _buffer[(_head + i) % _capacity];
    }
    _buffer = newBuffer;
    _capacity = newCapacity;
    _head = 0;
  }

  /// Removes and returns the oldest item from the buffer in O(1).
  RealtimeFrame? evictOldest() {
    if (_count == 0) return null;
    final item = _buffer[_head];
    _buffer[_head] = null;
    _head = (_head + 1) % _capacity;
    _count--;
    return item;
  }

  /// Accesses element at logical [index] in FIFO order (0 = oldest).
  RealtimeFrame operator [](int index) {
    if (index < 0 || index >= _count) {
      throw RangeError.index(index, this, 'index', null, _count);
    }
    return _buffer[(_head + index) % _capacity]!;
  }

  /// Replaces a frame by its [id] in-place, returning true if found.
  bool replaceById(String id, RealtimeFrame newFrame) {
    for (var i = 0; i < _count; i++) {
      final index = (_head + i) % _capacity;
      if (_buffer[index]?.id == id) {
        _buffer[index] = newFrame;
        return true;
      }
    }
    return false;
  }

  /// Updates maximum capacity, evicting oldest items if current count exceeds [newMaxCapacity].
  void updateMaxCapacity(int newMaxCapacity) {
    _maxCapacity = newMaxCapacity;
    while (_count > _maxCapacity) {
      evictOldest();
    }
    if (_capacity > _maxCapacity) {
      final newCapacity = _maxCapacity;
      final newBuffer = List<RealtimeFrame?>.filled(newCapacity, null);
      for (var i = 0; i < _count; i++) {
        newBuffer[i] = _buffer[(_head + i) % _capacity];
      }
      _buffer = newBuffer;
      _capacity = newCapacity;
      _head = 0;
    }
  }

  /// Clears all elements from the buffer.
  void clear() {
    _buffer.fillRange(0, _capacity, null);
    _head = 0;
    _count = 0;
  }
}

/// Zero-allocation, unmodifiable live [ListBase] view of a [DynamicCircularBuffer].
class _RealtimeBufferListView extends ListBase<RealtimeFrame> {
  _RealtimeBufferListView(this._store, this._sessionId);

  final RealtimeStore _store;
  final String _sessionId;

  DynamicCircularBuffer? get _buffer => _store._buffersBySession[_sessionId];

  @override
  int get length => _buffer?.count ?? 0;

  @override
  set length(int newLength) =>
      throw UnsupportedError('Realtime frame view is unmodifiable');

  @override
  RealtimeFrame operator [](int index) {
    final b = _buffer;
    if (b == null || index < 0 || index >= b.count) {
      throw RangeError.index(index, this, 'index', null, length);
    }
    return b[index];
  }

  @override
  void operator []=(int index, RealtimeFrame value) =>
      throw UnsupportedError('Realtime frame view is unmodifiable');
}

/// Clean-sheet in-memory realtime frame store with dynamic circular buffers,
/// zero-allocation ListBase views, and global budget coordination.
@internal
class RealtimeStore {
  /// Creates a [RealtimeStore] with [maxFramesPerSession] and [onThrottledBatch].
  RealtimeStore({
    required int maxFramesPerSession,
    required VoidCallback onThrottledBatch,
    int maxTotalRealtimeFrames = 5000,
    int maxSessions = 50,
  })  : _maxFramesPerSession = maxFramesPerSession,
        _onThrottledBatch = onThrottledBatch,
        _maxTotalRealtimeFrames = maxTotalRealtimeFrames,
        _maxSessions = maxSessions;

  int _maxFramesPerSession;
  int _maxTotalRealtimeFrames;
  int _maxSessions;
  final VoidCallback _onThrottledBatch;

  final Map<String, DynamicCircularBuffer> _buffersBySession = {};
  final Map<String, _RealtimeBufferListView> _viewsBySession = {};
  final Map<String, ValueNotifier<RealtimeFrameCounts>> _notifiersBySession = {};
  final Map<String, RealtimeFrameCounts> _liveCountsBySession = {};
  final Set<String> _dirtyNotifierSessions = {};
  final Set<String> _closedSessions = {};

  int _totalFramesAcrossSessions = 0;
  String? _lastActiveSessionId;
  Timer? _throttleTimer;
  bool _hasPendingNotification = false;
  bool _isDisposed = false;

  /// Total count of frames stored across all sessions.
  int get totalFramesAcrossSessions => _totalFramesAcrossSessions;

  DynamicCircularBuffer _getOrCreateBuffer(String sessionId) {
    var buffer = _buffersBySession[sessionId];
    if (buffer == null) {
      buffer = DynamicCircularBuffer(maxCapacity: _maxFramesPerSession);
      _buffersBySession[sessionId] = buffer;
      _lastActiveSessionId = sessionId;
    } else if (_lastActiveSessionId != sessionId) {
      _buffersBySession.remove(sessionId);
      _buffersBySession[sessionId] = buffer;
      _lastActiveSessionId = sessionId;
    }
    return buffer;
  }

  void _enforceMaxSessions({String? incomingSessionId}) {
    if (_buffersBySession.length <= _maxSessions) return;

    // 1. Evict any sessions with count == 0 first (queried empty views)
    final emptyKeys = <String>[];
    for (final entry in _buffersBySession.entries) {
      if (entry.key != incomingSessionId && entry.value.count == 0) {
        emptyKeys.add(entry.key);
      }
    }
    for (final key in emptyKeys) {
      _evictSession(key);
      if (_buffersBySession.length <= _maxSessions) return;
    }

    // 2. Evict closed sessions next
    final closedKeys = <String>[];
    for (final key in _buffersBySession.keys) {
      if (key != incomingSessionId && _closedSessions.contains(key)) {
        closedKeys.add(key);
      }
    }
    for (final key in closedKeys) {
      _evictSession(key);
      if (_buffersBySession.length <= _maxSessions) return;
    }

    // 3. Evict oldest sessions (FIFO in linked map)
    while (_buffersBySession.length > _maxSessions) {
      final keyToEvict = _buffersBySession.keys.firstWhere(
        (k) => k != incomingSessionId,
        orElse: () => _buffersBySession.keys.first,
      );
      _evictSession(keyToEvict);
    }
  }

  void _evictSession(String sessionId) {
    if (_lastActiveSessionId == sessionId) {
      _lastActiveSessionId = null;
    }
    final buffer = _buffersBySession.remove(sessionId);
    if (buffer != null) {
      _totalFramesAcrossSessions -= buffer.count;
      buffer.clear();
    }
    _viewsBySession.remove(sessionId);
    _closedSessions.remove(sessionId);
    _dirtyNotifierSessions.remove(sessionId);
  }

  /// Appends [frame] to the session buffer, enforces global budget, and updates counters.
  void recordFrame(RealtimeFrame frame) {
    if (_isDisposed) return;

    final buffer = _getOrCreateBuffer(frame.sessionId);
    final countBefore = buffer.count;
    buffer.add(frame);
    final countAfter = buffer.count;

    if (countAfter > countBefore) {
      _totalFramesAcrossSessions++;
    }

    _enforceMaxSessions(incomingSessionId: frame.sessionId);
    _enforceGlobalBudget();

    // Update live counts and mark session notifier as dirty for coalesced update
    final currentCounts =
        _liveCountsBySession[frame.sessionId] ?? const RealtimeFrameCounts();
    _liveCountsBySession[frame.sessionId] =
        currentCounts.copyWithIncrement(direction: frame.direction);
    _dirtyNotifierSessions.add(frame.sessionId);

    _scheduleNotification();
  }

  /// Replaces an existing frame in the session buffer (e.g. after offloading to disk).
  bool replaceFrame(RealtimeFrame newFrame) {
    if (_isDisposed) return false;
    final buffer = _buffersBySession[newFrame.sessionId];
    if (buffer == null) return false;
    return buffer.replaceById(newFrame.id, newFrame);
  }

  void _enforceGlobalBudget() {
    if (_totalFramesAcrossSessions <= _maxTotalRealtimeFrames ||
        _totalFramesAcrossSessions <= 0) {
      return;
    }

    final deficit = _totalFramesAcrossSessions - _maxTotalRealtimeFrames;
    var remainingDeficit = deficit;

    // 1. Evict from closed sessions first
    for (final closedKey in _closedSessions) {
      if (remainingDeficit <= 0) break;
      final buf = _buffersBySession[closedKey];
      if (buf != null && buf.count > 0) {
        final toEvict =
            buf.count < remainingDeficit ? buf.count : remainingDeficit;
        for (var i = 0; i < toEvict; i++) {
          buf.evictOldest();
        }
        _totalFramesAcrossSessions -= toEvict;
        remainingDeficit -= toEvict;
      }
    }

    // 2. If deficit remains, evict from least-recently-used active sessions (O(1) LRU)
    if (remainingDeficit > 0) {
      for (final key in _buffersBySession.keys) {
        if (remainingDeficit <= 0) break;
        final buf = _buffersBySession[key];
        if (buf != null && buf.count > 0) {
          final toEvict =
              buf.count < remainingDeficit ? buf.count : remainingDeficit;
          for (var i = 0; i < toEvict; i++) {
            buf.evictOldest();
          }
          _totalFramesAcrossSessions -= toEvict;
          remainingDeficit -= toEvict;
        }
      }
    }
  }

  void _scheduleNotification() {
    if (_isDisposed) return;
    _hasPendingNotification = true;
    _throttleTimer ??= Timer(const Duration(milliseconds: 100), () {
      _throttleTimer = null;
      if (_hasPendingNotification && !_isDisposed) {
        _hasPendingNotification = false;
        for (final sessionId in _dirtyNotifierSessions) {
          final notifier = _notifiersBySession[sessionId];
          final liveCount = _liveCountsBySession[sessionId];
          if (notifier != null && liveCount != null) {
            notifier.value = liveCount;
          }
        }
        _dirtyNotifierSessions.clear();
        _onThrottledBatch();
      }
    });
  }

  /// Returns an unmodifiable, live [ListBase] view of the captured frames for [sessionId].
  List<RealtimeFrame> getRealtimeFrames(String sessionId) {
    if (_isDisposed) return const <RealtimeFrame>[];
    return _viewsBySession.putIfAbsent(
      sessionId,
      () => _RealtimeBufferListView(this, sessionId),
    );
  }

  /// Returns the per-session [ValueListenable] for reactive frame count updates.
  ValueListenable<RealtimeFrameCounts> getFrameCountsNotifier(String sessionId) {
    return _notifiersBySession.putIfAbsent(
      sessionId,
      () => ValueNotifier(
        _liveCountsBySession[sessionId] ?? const RealtimeFrameCounts(),
      ),
    );
  }

  /// Returns the current total incoming and outgoing frame counts for [sessionId].
  RealtimeFrameCounts getFrameCounts(String sessionId) {
    if (_isDisposed) return const RealtimeFrameCounts();
    return _liveCountsBySession[sessionId] ?? const RealtimeFrameCounts();
  }

  /// Marks [sessionId] as closed, prioritizing its frames for eviction under memory pressure.
  void markSessionClosed(String sessionId) {
    _closedSessions.add(sessionId);
  }

  /// Updates maximum capacity for all current and future session buffers.
  void updateMaxFramesPerSession(int maxFrames) {
    _maxFramesPerSession = maxFrames;
    var newTotal = 0;
    for (final buffer in _buffersBySession.values) {
      buffer.updateMaxCapacity(maxFrames);
      newTotal += buffer.count;
    }
    _totalFramesAcrossSessions = newTotal;
    _enforceGlobalBudget();
  }

  /// Updates global limits across all realtime sessions.
  void updateGlobalCapacity({int? maxTotalFrames, int? maxSessions}) {
    if (maxTotalFrames != null && maxTotalFrames > 0) {
      _maxTotalRealtimeFrames = maxTotalFrames;
      _enforceGlobalBudget();
    }
    if (maxSessions != null && maxSessions > 0) {
      _maxSessions = maxSessions;
      _enforceMaxSessions();
    }
  }

  /// Clears all stored frames and resets session tracking.
  void clear() {
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _hasPendingNotification = false;
    _dirtyNotifierSessions.clear();
    _liveCountsBySession.clear();
    for (final buffer in _buffersBySession.values) {
      buffer.clear();
    }
    _buffersBySession.clear();
    _viewsBySession.clear();
    for (final notifier in _notifiersBySession.values) {
      notifier.value = const RealtimeFrameCounts();
    }
    _closedSessions.clear();
    _totalFramesAcrossSessions = 0;
  }

  /// Disposes the store, canceling background timers and clearing buffers.
  void dispose() {
    _isDisposed = true;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    for (final notifier in _notifiersBySession.values) {
      notifier.dispose();
    }
    _notifiersBySession.clear();
    clear();
  }
}
