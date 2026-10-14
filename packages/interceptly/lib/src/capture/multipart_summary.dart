import 'dart:convert';
import 'dart:typed_data';

/// Metadata for an individual multipart file payload.
class MultipartFileInfo {
  /// Creates metadata for a multipart file part.
  const MultipartFileInfo({
    required this.field,
    this.filename,
    this.contentType,
    this.length,
  });

  /// The name of the form field.
  final String field;

  /// The original filename if provided.
  final String? filename;

  /// The MIME type of the file.
  final String? contentType;

  /// The byte length of the file if known.
  final int? length;
}

/// Generates a standardized, human-readable summary of multipart fields and files
/// without consuming or buffering file streams.
Uint8List summarizeMultipart({
  Iterable<MapEntry<String, String>> fields = const [],
  Iterable<MultipartFileInfo> files = const [],
}) {
  final parts = <String>[];
  for (final field in fields) {
    parts.add('[field] ${field.key}=${field.value}');
  }
  for (final file in files) {
    final ct = file.contentType ?? 'application/octet-stream';
    final name = file.filename ?? 'blob';
    final size = file.length != null ? ', ${file.length} bytes' : '';
    parts.add('[file] ${file.field}: $name ($ct$size)');
  }
  return utf8.encode(parts.join('\n'));
}
