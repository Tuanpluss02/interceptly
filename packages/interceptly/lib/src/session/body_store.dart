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
  static const kFileName = 'interceptly_session.tmp';

  /// Maximum temporary file size in bytes before automatic rotation occurs.
  /// Defaults to 100 MB.
  static const int kMaxFileBytes = 100 * 1024 * 1024;

  BodyStore({int maxFileBytes = kMaxFileBytes}) : _maxFileBytes = maxFileBytes;

  final int _maxFileBytes;
  late File _file;
  RandomAccessFile? _raf;
  int _currentOffset = 0;
  int _rotationCount = 0;

  /// Current byte offset in the active file.
  int get currentOffset => _currentOffset;

  /// Maximum byte capacity before rotation occurs.
  int get maxFileBytes => _maxFileBytes;

  /// Number of times the file has rotated due to exceeding [maxFileBytes].
  int get rotationCount => _rotationCount;

  /// Opens (or recreates) the temp file for writing.
  ///
  /// [dirPath] must be resolved on the **main isolate** before the
  /// WriterIsolate is spawned, then passed in via the init message.
  Future<void> initForWrite(String dirPath,
      {String fileName = kFileName}) async {
    _file = File('$dirPath/$fileName');
    if (await _file.exists()) await _file.delete();
    await _file.create(recursive: true);
    _raf = await _file.open(mode: FileMode.writeOnlyAppend);
    _currentOffset = 0;
    _rotationCount = 0;
  }

  /// Appends [bytes] to the file.
  ///
  /// If appending [bytes] causes the file size to exceed [maxFileBytes],
  /// the file is automatically rotated (truncated to 0 bytes) and the offset resets to 0.
  /// Returns the (offset, length) needed to read the data back later.
  Future<(int, int)> append(Uint8List bytes) async {
    assert(_raf != null, 'initForWrite() must be called first');
    if (_currentOffset + bytes.length > _maxFileBytes) {
      await rotate();
    }
    final offset = _currentOffset;
    final length = bytes.length;
    await _raf!.writeFrom(bytes);
    _currentOffset += length;
    return (offset, length);
  }

  /// Closes the current file and recreates it empty at offset 0.
  Future<void> rotate() async {
    await _raf?.close();
    _raf = null;
    _currentOffset = 0;
    _rotationCount++;
    try {
      if (await _file.exists()) {
        await _file.delete();
      }
      await _file.create(recursive: true);
      _raf = await _file.open(mode: FileMode.writeOnlyAppend);
    } catch (_) {}
  }

  /// Resets the file: deletes and recreates it.
  Future<void> resetFile(String dirPath, {String fileName = kFileName}) async {
    await _raf?.close();
    _raf = null;
    _currentOffset = 0;
    _file = File('$dirPath/$fileName');
    if (await _file.exists()) await _file.delete();
    await _file.create(recursive: true);
    _raf = await _file.open(mode: FileMode.writeOnlyAppend);
  }

  Future<void> dispose() async {
    await _raf?.close();
    _raf = null;
    try {
      if (await _file.exists()) await _file.delete();
    } catch (_) {}
  }

  /// Opens a file for reading and returns an open [RandomAccessFile] handle.
  static Future<RandomAccessFile> openReadHandle(String filePath) async {
    return File(filePath).open(mode: FileMode.read);
  }

  /// Reads [length] bytes starting at [offset] from the open [raf] handle.
  static Future<Uint8List> readWithHandle(
    RandomAccessFile raf,
    int offset,
    int length,
  ) async {
    await raf.setPosition(offset);
    return raf.read(length);
  }

  /// Reads [length] bytes starting at [offset] from [filePath].
  ///
  /// Called by [InspectorSession.loadDetail] on the main isolate.
  /// Creates a read-only handle and closes it immediately after.
  static Future<Uint8List> readBytes(
    String filePath,
    int offset,
    int length,
  ) async {
    final raf = await openReadHandle(filePath);
    try {
      return await readWithHandle(raf, offset, length);
    } finally {
      await raf.close();
    }
  }

  /// Detects and purges orphaned temporary session files in [dirPath].
  ///
  /// Removes files prefixed with `interceptly_` and ending with `.tmp`,
  /// excluding [currentFileName]. If [maxAge] is provided, only files
  /// whose last modified time is older than [maxAge] are deleted.
  /// Gracefully handles [FileSystemException] and returns the count of purged files.
  static Future<int> purgeOrphanedTempFiles(
    String dirPath, {
    String? currentFileName,
    Duration? maxAge,
  }) async {
    var purgedCount = 0;
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return 0;

      final entities = await dir.list().toList();
      final activeBaseName = currentFileName?.split(RegExp(r'[/\\]')).last;
      final threshold = maxAge != null ? DateTime.now().subtract(maxAge) : null;

      for (final entity in entities) {
        if (entity is File) {
          final fileName = entity.path.split(RegExp(r'[/\\]')).last;
          if (fileName.startsWith('interceptly_') &&
              fileName.endsWith('.tmp') &&
              (activeBaseName == null || fileName != activeBaseName)) {
            try {
              if (threshold != null) {
                final lastModified = entity.lastModifiedSync();
                if (!lastModified.isBefore(threshold)) {
                  continue;
                }
              }
              await entity.delete();
              purgedCount++;
            } on FileSystemException {
              continue;
            } catch (_) {
              continue;
            }
          }
        }
      }
    } on FileSystemException {
      return purgedCount;
    } catch (_) {
      return purgedCount;
    }
    return purgedCount;
  }
}
