import 'dart:io';
import 'dart:typed_data';

/// Append-only binary store backed by a single temp file.
///
/// **Important:** [initForWrite] must be called from the WRITER ISOLATE with
/// a pre-resolved [dirPath] — do NOT call [getTemporaryDirectory] inside
/// the isolate (platform channel not available).
///
/// Reading is done exclusively from the main isolate via the static
/// [readBytes] helper, which never modifies the file.
class BodyStore {
  static const kFileName = 'netspecter_session.tmp';

  late File _file;
  RandomAccessFile? _raf;
  int _currentOffset = 0;

  /// Opens (or recreates) the temp file for writing.
  ///
  /// [dirPath] must be resolved on the **main isolate** before the
  /// WriterIsolate is spawned, then passed in via the init message.
  Future<void> initForWrite(String dirPath) async {
    _file = File('$dirPath/$kFileName');
    if (await _file.exists()) await _file.delete();
    await _file.create(recursive: true);
    _raf = await _file.open(mode: FileMode.writeOnlyAppend);
    _currentOffset = 0;
  }

  /// Appends [bytes] to the file.
  /// Returns the (offset, length) needed to read the data back later.
  Future<(int, int)> append(Uint8List bytes) async {
    assert(_raf != null, 'initForWrite() must be called first');
    final offset = _currentOffset;
    final length = bytes.length;
    await _raf!.writeFrom(bytes);
    _currentOffset += length;
    return (offset, length);
  }

  /// Resets the file: deletes and recreates it.
  Future<void> resetFile(String dirPath) async {
    await _raf?.close();
    _raf = null;
    _currentOffset = 0;
    _file = File('$dirPath/$kFileName');
    if (await _file.exists()) await _file.delete();
    await _file.create(recursive: true);
    _raf = await _file.open(mode: FileMode.writeOnlyAppend);
  }

  Future<void> dispose() async {
    await _raf?.close();
    _raf = null;
    if (await _file.exists()) await _file.delete();
  }

  // ---------------------------------------------------------------------------
  // Static read helper — called from the MAIN ISOLATE, never modifies the file
  // ---------------------------------------------------------------------------

  /// Reads [length] bytes starting at [offset] from [filePath].
  ///
  /// Called by [InspectorSession.loadDetail] on the main isolate.
  /// Creates a read-only handle and closes it immediately after.
  static Future<Uint8List> readBytes(
    String filePath,
    int offset,
    int length,
  ) async {
    final raf = await File(filePath).open(mode: FileMode.read);
    try {
      await raf.setPosition(offset);
      return await raf.read(length);
    } finally {
      await raf.close();
    }
  }
}
