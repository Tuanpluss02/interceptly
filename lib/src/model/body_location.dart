/// Where body bytes are persisted for a captured request.
enum BodyLocation {
  /// Small body (<50KB), kept inline in memory.
  memory,

  /// Large body (≥50KB), stored in temp file with offset and length.
  file,
}
