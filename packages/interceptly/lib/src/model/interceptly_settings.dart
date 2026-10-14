/// Configuration for Interceptly capture and storage behavior.
class InterceptlySettings {
  const InterceptlySettings({
    this.bodyOffloadThreshold = 50 * 1024,
    this.previewTruncationBytes = 16 * 1024,
    this.maxBodyBytes = 5 * 1024 * 1024,
    this.maxUiPreviewBytes = 2 * 1024 * 1024,
    this.maxQueuedEvents = 500,
    this.maxEntries = 5000,
    this.maxFramesPerSession = 1000,
    this.urlDecodeEnabled = true,
    this.pendingTimeout = const Duration(seconds: 45),
    this.shouldCapture,
    this.persistToDisk = true,
  })  : assert(maxEntries > 0, 'maxEntries must be greater than 0'),
        assert(maxQueuedEvents > 0, 'maxQueuedEvents must be greater than 0'),
        assert(
          maxFramesPerSession > 0,
          'maxFramesPerSession must be greater than 0',
        ),
        assert(
          previewTruncationBytes >= 0,
          'previewTruncationBytes must be non-negative',
        ),
        assert(
          bodyOffloadThreshold >= 0,
          'bodyOffloadThreshold must be non-negative',
        ),
        assert(
          maxUiPreviewBytes >= 0,
          'maxUiPreviewBytes must be non-negative',
        );

  /// Body size (bytes) above which data is offloaded to the temp file.
  /// Below this threshold the raw bytes are kept inline in RAM.
  final int bodyOffloadThreshold;

  /// Inline byte budget for pending request rows still waiting for a response.
  /// When a pending body exceeds [maxBodyBytes], only this many leading bytes
  /// are kept in RAM; smaller bodies are kept whole.
  final int previewTruncationBytes;

  /// Hard cap: bodies larger than this are truncated before storage.
  /// Defaults to 5 MB (5 * 1024 * 1024). Values <= 0 indicate unlimited storage.
  final int maxBodyBytes;

  /// Maximum payload bytes rendered in the UI preview to avoid UI lag.
  /// Defaults to 2 MB (2 * 1024 * 1024).
  final int maxUiPreviewBytes;

  /// Maximum number of pending capture events in the writer queue.
  /// When full, the oldest unprocessed item is dropped.
  final int maxQueuedEvents;

  /// Maximum number of `IndexEntry` items kept in the in-memory index.
  /// When exceeded, the oldest entry is removed.
  final int maxEntries;

  /// Maximum number of `RealtimeFrame` items kept in memory per realtime session.
  /// When exceeded, the oldest frame in the session is evicted.
  /// Defaults to 1000.
  final int maxFramesPerSession;

  /// Whether to decode URL encodings in the UI.
  final bool urlDecodeEnabled;

  /// Duration after which an uncompleted pending request is marked as timed out.
  final Duration pendingTimeout;

  /// Optional predicate to exclude URLs or requests from being captured.
  ///
  /// Evaluated synchronously on every request URL before capture processing.
  /// If [shouldCapture] returns `false`, the request is completely ignored and
  /// not stored in memory, pending tracker, or background storage.
  ///
  /// Note: The predicate must be lightweight and fast to avoid adding latency
  /// to request initiation. It receives the request URL string before sanitization.
  final bool Function(String url)? shouldCapture;

  /// Whether to persist offloaded request/response bodies to a temporary file on disk.
  ///
  /// When `true` (the default), payloads exceeding [bodyOffloadThreshold] are
  /// streamed to a session-scoped temporary file to conserve RAM.
  ///
  /// When `false` (memory-only mode), all captured payloads are retained inline in
  /// memory up to [maxBodyBytes], and no disk writes or temporary files are created.
  final bool persistToDisk;

  /// Convenience getter indicating whether memory-only mode is active.
  /// Equivalent to `!persistToDisk`.
  bool get memoryOnly => !persistToDisk;

  InterceptlySettings copyWith({
    int? bodyOffloadThreshold,
    int? previewTruncationBytes,
    int? maxBodyBytes,
    int? maxUiPreviewBytes,
    int? maxQueuedEvents,
    int? maxEntries,
    int? maxFramesPerSession,
    bool? urlDecodeEnabled,
    Duration? pendingTimeout,
    bool Function(String url)? shouldCapture,
    bool? persistToDisk,
  }) {
    return InterceptlySettings(
      bodyOffloadThreshold: bodyOffloadThreshold ?? this.bodyOffloadThreshold,
      previewTruncationBytes:
          previewTruncationBytes ?? this.previewTruncationBytes,
      maxBodyBytes: maxBodyBytes ?? this.maxBodyBytes,
      maxUiPreviewBytes: maxUiPreviewBytes ?? this.maxUiPreviewBytes,
      maxQueuedEvents: maxQueuedEvents ?? this.maxQueuedEvents,
      maxEntries: maxEntries ?? this.maxEntries,
      maxFramesPerSession: maxFramesPerSession ?? this.maxFramesPerSession,
      urlDecodeEnabled: urlDecodeEnabled ?? this.urlDecodeEnabled,
      pendingTimeout: pendingTimeout ?? this.pendingTimeout,
      shouldCapture: shouldCapture ?? this.shouldCapture,
      persistToDisk: persistToDisk ?? this.persistToDisk,
    );
  }
}
