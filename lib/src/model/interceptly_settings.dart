/// Configuration for Interceptly capture and storage behavior.
class InterceptlySettings {
  const InterceptlySettings({
    this.bodyOffloadThreshold = 50 * 1024,
    this.previewTruncationBytes = 16 * 1024,
    this.maxBodyBytes = 2 * 1024 * 1024,
    this.maxQueuedEvents = 500,
    this.maxEntries = 5000,
    this.urlDecodeEnabled = true,
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

  InterceptlySettings copyWith({
    int? bodyOffloadThreshold,
    int? previewTruncationBytes,
    int? maxBodyBytes,
    int? maxQueuedEvents,
    int? maxEntries,
    bool? urlDecodeEnabled,
  }) {
    return InterceptlySettings(
      bodyOffloadThreshold: bodyOffloadThreshold ?? this.bodyOffloadThreshold,
      previewTruncationBytes:
          previewTruncationBytes ?? this.previewTruncationBytes,
      maxBodyBytes: maxBodyBytes ?? this.maxBodyBytes,
      maxQueuedEvents: maxQueuedEvents ?? this.maxQueuedEvents,
      maxEntries: maxEntries ?? this.maxEntries,
      urlDecodeEnabled: urlDecodeEnabled ?? this.urlDecodeEnabled,
    );
  }
}
