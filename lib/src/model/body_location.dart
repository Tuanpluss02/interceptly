enum BodyLocation {
  /// Body nhỏ (<50KB) — giữ thẳng trong RAM dưới dạng Uint8List.
  memory,

  /// Body lớn (≥50KB) — chỉ lưu offset + length, dữ liệu trong temp file.
  file,
}
