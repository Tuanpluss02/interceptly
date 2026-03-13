class NetSpecterSettings {
  const NetSpecterSettings({
    this.bodyOffloadThreshold = 50 * 1024,
    this.previewTruncationBytes = 16 * 1024,
    this.maxBodyBytes = 2 * 1024 * 1024,
    this.maxQueuedEvents = 500,
    this.maxEntries = 5000,
  });

  /// Body size (bytes) above which data is offloaded to the temp file.
  /// Below this threshold the raw bytes are kept inline in RAM.
  final int bodyOffloadThreshold;

  /// Max characters shown in the body preview before '[truncated]' suffix.
  final int previewTruncationBytes;

  /// Hard cap: bodies larger than this are truncated before storage.
  final int maxBodyBytes;

  /// Maximum number of pending [RawCapture]s in the writer queue.
  /// When full, the oldest unprocessed item is dropped.
  final int maxQueuedEvents;

  /// Maximum number of [IndexEntry]s kept in the [MemoryIndex].
  /// When exceeded, the oldest entry is removed.
  final int maxEntries;
}
