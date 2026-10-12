/// Which stage dropped bytes from a captured body.
enum TruncationStage {
  /// Nothing was dropped; the body is complete at every stage.
  none,

  /// Storage kept the whole body; only the detail-view preview was shortened.
  /// Exports and replay still see the complete payload.
  preview,

  /// The body exceeded `maxBodyBytes` and was cut before it reached storage.
  /// The original payload is unrecoverable.
  storage,

  /// Both stages dropped bytes.
  storageAndPreview,
}

/// How much of a single body survived, and where it was cut.
///
/// One value describes one side of an exchange (request or response), so a UI
/// can place its notice on the exact panel that is incomplete instead of
/// describing the whole record in one lump.
class BodyTruncation {
  const BodyTruncation({
    required this.originalBytes,
    required this.retainedBytes,
    required this.stage,
  });

  /// Body was fully captured and displayed as-is.
  const BodyTruncation.complete(this.originalBytes)
      : retainedBytes = originalBytes,
        stage = TruncationStage.none;

  final int originalBytes;

  /// Bytes the detail view can actually render, after preview trimming.
  ///
  /// Never exceeds [originalBytes]. Equal to [originalBytes] whenever
  /// [stage] is [TruncationStage.none] or [TruncationStage.storage], so a
  /// storage-only cut is reported as "you see everything that survived",
  /// with the loss described by [stage] instead.
  final int retainedBytes;

  final TruncationStage stage;

  /// True when the original payload cannot be reproduced from stored data.
  ///
  /// Guards replay and export: a body cut at the storage stage will send
  /// different bytes than the server originally received.
  bool get hasDataLoss =>
      stage == TruncationStage.storage ||
      stage == TruncationStage.storageAndPreview;

  /// True when only the rendered preview is shorter than the real payload.
  bool get isPreviewOnly => stage == TruncationStage.preview;

  bool get isTruncated => stage != TruncationStage.none;
}
