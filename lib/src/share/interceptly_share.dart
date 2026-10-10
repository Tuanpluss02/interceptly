import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class InterceptlyShare {
  InterceptlyShare({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'dev.stormx.interceptly/share';

  final MethodChannel _channel;

  @visibleForTesting
  MethodChannel get debugChannel => _channel;

  @visibleForTesting
  static bool? debugMobileOverride;

  Future<bool> shareFile({
    required String filePath,
    String? subject,
    String? text,
    String? mimeType,
    Rect? origin,
  }) async {
    final isMobile =
        debugMobileOverride ?? (!kIsWeb && (Platform.isAndroid || Platform.isIOS));
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
