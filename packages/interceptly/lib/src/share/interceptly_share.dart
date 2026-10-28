import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Service for sharing files via platform share sheets.
///
/// File paths are validated to reside within the system temporary directory
/// using canonicalized paths and `isWithin` checks to prevent traversal.
class InterceptlyShare {
  InterceptlyShare({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'dev.stormx.interceptly/share';

  final MethodChannel _channel;

  /// Default file size limit for shared files (50 MB).
  static const int defaultMaxFileSizeBytes = 50 * 1024 * 1024;

  /// Validates whether [filePath] is contained safely within a temporary directory.
  ///
  /// Both candidate and trusted roots are canonicalized with
  /// `resolveSymbolicLinksSync` and compared with `isWithin`, including a
  /// trailing separator, so `/tmp2` cannot masquerade as `/tmp`.
  static bool isWithinTempDirectory(String filePath) {
    if (filePath.contains('..')) return false;

    /// Resolves [target] to a canonical path, falling back to parent
    /// resolution when the file itself does not exist yet.
    ///
    /// Non-existent export targets cannot be resolved directly, so the
    /// parent directory symlink (for example `/tmp` to `/private/tmp`
    /// on macOS) is resolved and joined with the basename.
    String canonicalOf(String target) {
      try {
        return Directory(target).resolveSymbolicLinksSync();
      } catch (_) {}
      try {
        return File(target).resolveSymbolicLinksSync();
      } catch (_) {}
      try {
        final parent = File(target).absolute.parent;
        final resolvedParent = parent.resolveSymbolicLinksSync();
        return p.join(resolvedParent, p.basename(target));
      } catch (_) {
        return File(target).absolute.path;
      }
    }

    String withSeparator(String dirPath) {
      if (dirPath.endsWith(Platform.pathSeparator)) return dirPath;
      return '$dirPath${Platform.pathSeparator}';
    }

    final canonicalFile = canonicalOf(filePath);
    final roots = <String>[
      Directory.systemTemp.path,
      '/tmp',
      '/private/tmp',
      '/var/tmp',
      '/data/local/tmp',
    ];
    for (final root in roots) {
      final canonicalRoot = canonicalOf(root);
      if (canonicalFile == canonicalRoot) return true;
      if (p.isWithin(withSeparator(canonicalRoot), canonicalFile) ||
          p.isWithin(canonicalRoot, canonicalFile)) {
        return true;
      }
    }
    return false;
  }

  /// Presents a native share sheet for the file at [filePath].
  ///
  /// Throws [ArgumentError] if [filePath] does not reside within the temporary directory.
  /// Throws [StateError] if the file exceeds [maxFileSizeBytes].
  Future<bool> shareFile({
    required String filePath,
    String? subject,
    String? text,
    String? mimeType,
    Rect? origin,
    int maxFileSizeBytes = defaultMaxFileSizeBytes,
  }) async {
    if (!isWithinTempDirectory(filePath)) {
      throw ArgumentError(
        'Shared file path must reside within the temporary directory: $filePath',
      );
    }

    final file = File(filePath);
    if (await file.exists()) {
      final size = await file.length();
      if (size > maxFileSizeBytes) {
        throw StateError(
          'File size ($size bytes) exceeds maximum share limit ($maxFileSizeBytes bytes)',
        );
      }
    }

    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (!isMobile) return false;

    try {
      final result = await _channel.invokeMethod<bool>('shareFile', {
        'path': filePath,
        'subject': subject,
        'text': text,
        'mimeType': mimeType ?? _mimeFor(filePath),
        'originX': origin?.left,
        'originY': origin?.top,
        'originWidth': origin?.width,
        'originHeight': origin?.height,
      });
      return result ?? false;
    } on MissingPluginException catch (_) {
      debugPrint('InterceptlyShare: native plugin not registered');
      return false;
    } on PlatformException catch (e) {
      debugPrint('InterceptlyShare: share failed: ${e.message}');
      return false;
    }
  }

  static String _mimeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.json') ||
        lower.endsWith('.har') ||
        lower.endsWith('.postman_collection.json')) {
      return 'application/json';
    }
    if (lower.endsWith('.txt')) return 'text/plain';
    return '*/*';
  }
}
