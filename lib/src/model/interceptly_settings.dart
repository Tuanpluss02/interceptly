/// Configuration for Interceptly capture and storage behavior.
class InterceptlySettings {
  const InterceptlySettings({
    this.bodyOffloadThreshold = 50 * 1024,
    this.previewTruncationBytes = 16 * 1024,
    this.maxBodyBytes = 5 * 1024 * 1024,
    this.maxUiPreviewBytes = 2 * 1024 * 1024,
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

  /// Whether to decode URL encodings in the UI.
  final bool urlDecodeEnabled;

  /// Duration after which an uncompleted pending request is marked as timed out.
  final Duration pendingTimeout;

  /// Header names (case-insensitive) whose values should be redacted with `[REDACTED]`.
  final Set<String> redactedHeaders;

  static final Expando<Set<String>> _normalizedCache = Expando<Set<String>>();

  /// Pre-normalized lowercase set of [redactedHeaders] for fast case-insensitive lookup.
  Set<String> get normalizedRedactedHeaders => _normalizedCache[this] ??=
      Set<String>.unmodifiable(redactedHeaders.map((k) => k.toLowerCase()));

  /// Optional predicate to exclude URLs or requests from being captured.
  final bool Function(String url)? shouldCapture;

  InterceptlySettings copyWith({
    int? bodyOffloadThreshold,
    int? previewTruncationBytes,
    int? maxBodyBytes,
    int? maxUiPreviewBytes,
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
      maxUiPreviewBytes: maxUiPreviewBytes ?? this.maxUiPreviewBytes,
      maxQueuedEvents: maxQueuedEvents ?? this.maxQueuedEvents,
      maxEntries: maxEntries ?? this.maxEntries,
      urlDecodeEnabled: urlDecodeEnabled ?? this.urlDecodeEnabled,
      pendingTimeout: pendingTimeout ?? this.pendingTimeout,
      redactedHeaders: redactedHeaders ?? this.redactedHeaders,
      shouldCapture: shouldCapture ?? this.shouldCapture,
    );
  }
}
