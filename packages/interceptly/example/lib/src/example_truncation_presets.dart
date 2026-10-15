import 'package:interceptly/interceptly.dart';

/// A named size-limit configuration used to exercise a specific truncation
/// stage end to end in the example app.
///
/// `maxBodyBytes` decides what survives storage; `maxUiPreviewBytes` decides
/// how much of the stored body the detail view decodes. The two caps interact,
/// so each preset pins a distinct combination.
class TruncationPreset {
  const TruncationPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.maxBodyBytes,
    required this.maxUiPreviewBytes,
  });

  final String id;
  final String label;

  /// What the detail view is expected to show for this configuration.
  final String description;

  final int maxBodyBytes;
  final int maxUiPreviewBytes;

  /// The stage a ~6 MB response should be reported at, or `null` when no cut is
  /// expected at all. Doubles as documentation for whoever runs the example.
  TruncationStage? get expectedStage {
    final sixMb = 6 * 1024 * 1024;
    final storageCuts = maxBodyBytes > 0 && maxBodyBytes < sixMb;
    final previewCuts = maxUiPreviewBytes > 0 && maxUiPreviewBytes < sixMb;
    if (storageCuts && previewCuts) return TruncationStage.storageAndPreview;
    if (storageCuts) return TruncationStage.storage;
    if (previewCuts) return TruncationStage.preview;
    return TruncationStage.none;
  }

  InterceptlySettings toSettings() {
    return InterceptlySettings(
      maxBodyBytes: maxBodyBytes,
      maxUiPreviewBytes: maxUiPreviewBytes,
      shouldCapture: (url) => !url.contains('/analytics'),
    );
  }
}

/// Presets covering each truncation stage, ordered from "no cut" to
/// "cut at both stages".
const truncationPresets = <TruncationPreset>[
  TruncationPreset(
    id: 'no_limits',
    label: 'No limits',
    description: 'Both caps lifted — the ~6 MB response shows in full.',
    maxBodyBytes: 50 * 1024 * 1024,
    maxUiPreviewBytes: 50 * 1024 * 1024,
  ),
  TruncationPreset(
    id: 'preview_only',
    label: 'Preview only',
    description: 'Storage keeps everything; only the detail view is capped. '
        'Expect a grey notice saying nothing is lost.',
    maxBodyBytes: 50 * 1024 * 1024,
    maxUiPreviewBytes: 400 * 1024,
  ),
  TruncationPreset(
    id: 'storage_only',
    label: 'Storage only',
    description: 'Cut at maxBodyBytes before storage. Expect a yellow notice '
        'saying the rest was discarded.',
    maxBodyBytes: 2 * 1024 * 1024,
    maxUiPreviewBytes: 50 * 1024 * 1024,
  ),
  TruncationPreset(
    id: 'both',
    label: 'Both stages',
    description: 'Cut at maxBodyBytes and capped again for the preview. '
        'Expect the strongest wording: unrecoverable.',
    maxBodyBytes: 5 * 1024 * 1024,
    maxUiPreviewBytes: 1024 * 1024,
  ),
];
