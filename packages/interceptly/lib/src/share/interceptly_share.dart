import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service for sharing files via platform share sheets.
class InterceptlyShare {
  InterceptlyShare({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'dev.stormx.interceptly/share';

  final MethodChannel _channel;

  /// Default file size limit for shared files (50 MB).
  static const int defaultMaxFileSizeBytes = 50 * 1024 * 1024;

  /// Validates whether [filePath] is contained safely within a temporary directory.
  static bool isWithinTempDirectory(String filePath) {
    if (filePath.contains('..')) return false;

    final file = File(filePath);
    final absPath = file.absolute.path;

    final sysTemp = Directory.systemTemp.path;
    if (absPath.startsWith(sysTemp)) return true;

    try {
      final resolvedSysTemp = Directory.systemTemp.resolveSymbolicLinksSync();
      if (absPath.startsWith(resolvedSysTemp)) return true;
    } catch (_) {}

    if (absPath.startsWith('/tmp') ||
        absPath.startsWith('/private/tmp') ||
        absPath.startsWith('/var/tmp') ||
        absPath.startsWith('/data/local/tmp')) {
      return true;
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
