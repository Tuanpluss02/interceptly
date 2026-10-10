/// Configuration for Interceptly capture and storage behavior.
class InterceptlySettings {
  const InterceptlySettings({
    this.bodyOffloadThreshold = 50 * 1024,
    this.previewTruncationBytes = 16 * 1024,
    this.maxBodyBytes = 2 * 1024 * 1024,
    this.maxQueuedEvents = 500,
    this.maxEntries = 5000,
    this.urlDecodeEnabled = true,
    this.pendingTimeout = const Duration(seconds: 45),
    this.redactedHeaders = const {
      'authorization',
      'cookie',
      'set-cookie',
      'x-api-key',
    },
    this.shouldCapture,
  });

  /// Body size (bytes) above which data is offloaded to the temp file.
  /// Below this threshold the raw bytes are kept inline in RAM.
  final int bodyOffloadThreshold;

  /// Max characters shown in the body preview before the "truncated" suffix.
  final int previewTruncationBytes;

  /// Hard cap: bodies larger than this are truncated before storage.
  final int maxBodyBytes;

  /// Maximum number of pending [RawCapture]s in the writer queue.
  /// When full, the oldest unprocessed item is dropped.
  final int maxQueuedEvents;

  /// Maximum number of `IndexEntry` items kept in the in-memory index.
  /// When exceeded, the oldest entry is removed.
  final int maxEntries;

  /// Whether to decode URL encodings in the UI.
  final bool urlDecodeEnabled;

  /// Duration after which an uncompleted pending request is marked as timed out.
  final Duration pendingTimeout;

  /// Header names (case-insensitive) whose values should be redacted with `[REDACTED]`.
  final Set<String> redactedHeaders;

  /// Optional predicate to exclude URLs or requests from being captured.
  final bool Function(String url)? shouldCapture;

  InterceptlySettings copyWith({
    int? bodyOffloadThreshold,
    int? previewTruncationBytes,
    int? maxBodyBytes,
    int? maxQueuedEvents,
    int? maxEntries,
    bool? urlDecodeEnabled,
    Duration? pendingTimeout,
    Set<String>? redactedHeaders,
    bool Function(String url)? shouldCapture,
  }) {
    return InterceptlySettings(
      bodyOffloadThreshold: bodyOffloadThreshold ?? this.bodyOffloadThreshold,
      previewTruncationBytes:
          previewTruncationBytes ?? this.previewTruncationBytes,
      maxBodyBytes: maxBodyBytes ?? this.maxBodyBytes,
      maxQueuedEvents: maxQueuedEvents ?? this.maxQueuedEvents,
      maxEntries: maxEntries ?? this.maxEntries,
      urlDecodeEnabled: urlDecodeEnabled ?? this.urlDecodeEnabled,
      pendingTimeout: pendingTimeout ?? this.pendingTimeout,
      redactedHeaders: redactedHeaders ?? this.redactedHeaders,
      shouldCapture: shouldCapture ?? this.shouldCapture,
    );
  }
}
