import 'package:flutter/foundation.dart';

/// Pipeline generation fencing helpers.
///
/// Extracted to an io-free file so adapters importing
/// `HttpRequestContext` do not pull `dart:io` or `path_provider`
/// transitively. Must never be barrel-exported.
final Expando<int> _captureGenerationExpando = Expando<int>(
  'captureGeneration',
);

/// Associates a capture lifecycle object with the active pipeline [generation].
@internal
void attachCaptureGeneration(Object target, int? generation) {
  if (generation != null) {
    _captureGenerationExpando[target] = generation;
  }
}

/// Reads the pipeline generation previously attached to [target], if any.
@internal
int? readCaptureGeneration(Object target) => _captureGenerationExpando[target];
