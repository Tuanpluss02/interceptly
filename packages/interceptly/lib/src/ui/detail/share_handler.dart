import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../export/curl_generator.dart';
import '../../export/har_exporter.dart';
import '../../export/postman_exporter.dart';
import '../../model/request_record.dart';
import '../../share/interceptly_share.dart';
import '../interceptly_theme.dart';
import '../widgets/toast_notification.dart';

/// Coordinates sharing and exporting requests as cURL, HAR, or Postman files.
class ShareHandler {
  ShareHandler({
    required this.context,
    required this.fabKey,
    InterceptlyShare? share,
  }) : _share = share ?? InterceptlyShare();

  final BuildContext context;
  final GlobalKey fabKey;
  final InterceptlyShare _share;

  void showShareMenu(RequestRecord record) {
    showModalBottomSheet(
      context: context,
      backgroundColor: InterceptlyTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Theme(
        data: InterceptlyTheme.themeData(context: context),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: InterceptlyTheme.controlMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: Row(
                  children: [
                    Text(
                      'Share Request',
                      style:
                          InterceptlyTheme.typography.bodyMediumBold.copyWith(
                        color: InterceptlyTheme.textPrimary,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.copy,
                  color: InterceptlyTheme.indigo500,
                ),
                title: Text(
                  'Copy cURL',
                  style: InterceptlyTheme.typography.bodyMediumMedium.copyWith(
                    color: InterceptlyTheme.textPrimary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  shareCurlCommand(record);
                },
              ),
              Divider(color: InterceptlyTheme.dividerSubtle, height: 1),
              ListTile(
                leading: const Icon(
                  Icons.download,
                  color: InterceptlyTheme.indigo500,
                ),
                title: Text(
                  'Export HAR',
                  style: InterceptlyTheme.typography.bodyMediumMedium.copyWith(
                    color: InterceptlyTheme.textPrimary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  exportHarFile(record);
                },
              ),
              Divider(color: InterceptlyTheme.dividerSubtle, height: 1),
              ListTile(
                leading: const Icon(
                  Icons.upload_file,
                  color: InterceptlyTheme.indigo500,
                ),
                title: Text(
                  'Export Postman Collection',
                  style: InterceptlyTheme.typography.bodyMediumMedium.copyWith(
                    color: InterceptlyTheme.textPrimary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  exportPostmanFile(record);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void shareCurlCommand(RequestRecord record) {
    try {
      final curl = CurlGenerator.fromRecord(record);
      Clipboard.setData(ClipboardData(text: curl));
      ToastNotification.show('cURL command copied', contextHint: context);
    } catch (e) {
      ToastNotification.show('Error: $e', contextHint: context);
    }
  }

  void exportPostmanFile(RequestRecord record) async {
    await _exportPostmanRecords([record]);
  }

  Future<void> exportPostmanRecords(List<RequestRecord> records) async {
    await _exportPostmanRecords(records);
  }

  Future<void> _exportPostmanRecords(List<RequestRecord> records) async {
    File? file;
    var shareInitiated = false;
    try {
      final collectionMap = PostmanExporter.toMap(records);
      final collectionJson = await compute(_encodeJsonMap, collectionMap);

      final directory = await getTemporaryDirectory();
      await purgeStaleExports(directory);
      final fileName =
          'interceptly_${DateTime.now().millisecondsSinceEpoch}.postman_collection.json';
      file = File('${directory.path}/$fileName');

      final sink = file.openWrite();
      const chunkSize = 16 * 1024;
      for (var i = 0; i < collectionJson.length; i += chunkSize) {
        final end = (i + chunkSize < collectionJson.length)
            ? i + chunkSize
            : collectionJson.length;
        sink.write(collectionJson.substring(i, end));
      }
      await sink.flush();
      await sink.close();

      final origin = await _getSharePositionOrigin();
      shareInitiated = true;
      await _shareFile(
        file,
        subject: 'Postman Collection Export',
        text: 'Postman Collection export from Interceptly',
        origin: origin,
      );
    } catch (e) {
      if (!shareInitiated && file != null) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      ToastNotification.show('Error exporting Postman collection: $e');
    }
  }

  Future<void> exportHarFile(RequestRecord record) async {
    File? file;
    var shareInitiated = false;
    try {
      final harMap = HarExporter.toMap([record]);
      final harJson = await compute(_encodeJsonMap, harMap);

      final directory = await getTemporaryDirectory();
      await purgeStaleExports(directory);
      final sanitizedMethod = _sanitizeFilename(record.method);
      final fileName =
          'request_${sanitizedMethod}_${DateTime.now().millisecondsSinceEpoch}.har';
      file = File('${directory.path}/$fileName');

      final sink = file.openWrite();
      sink.write(harJson);
      await sink.flush();
      await sink.close();

      final origin = await _getSharePositionOrigin();
      shareInitiated = true;
      await _shareFile(
        file,
        subject: 'HAR Export',
        text: 'Network request HAR export',
        origin: origin,
      );
    } catch (e) {
      if (!shareInitiated && file != null) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      ToastNotification.show('Error exporting HAR: $e');
    }
  }

  /// Purges old export artifacts from [directory] to keep temp storage bounded.
  static Future<void> purgeStaleExports(
    Directory directory, {
    Duration maxAge = const Duration(hours: 1),
  }) async {
    try {
      if (!await directory.exists()) return;
      final now = DateTime.now();
      await for (final entity in directory.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (name.startsWith('interceptly_') || name.startsWith('request_')) {
            if (name.endsWith('.har') ||
                name.endsWith('.json') ||
                name.endsWith('.postman_collection') ||
                name.endsWith('.postman_collection.json')) {
              try {
                final stat = await entity.stat();
                if (now.difference(stat.modified) > maxAge) {
                  await entity.delete();
                }
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _shareFile(
    File file, {
    String? subject,
    String? text,
    String mimeType = 'application/json',
    Rect? origin,
  }) async {
    try {
      final presented = await _share.shareFile(
        filePath: file.path,
        subject: subject,
        text: text,
        mimeType: mimeType,
        origin: origin,
      );
      if (!presented) {
        if (context.mounted) {
          ToastNotification.show(
            'Share unavailable',
            contextHint: context,
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        ToastNotification.show('Share failed', contextHint: context);
      }
    }
  }

  Future<Rect> _getSharePositionOrigin() async {
    try {
      final box = fabKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        final offset = box.localToGlobal(Offset.zero);
        final size = box.size;
        return Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
      }
    } catch (e) {
      debugPrint('Error getting share position origin: $e');
    }
    return Rect.fromCenter(
      center: Offset(
        MediaQuery.of(context).size.width / 2,
        MediaQuery.of(context).size.height / 2,
      ),
      width: 1,
      height: 1,
    );
  }

  /// Replaces non-alphanumeric characters with underscores to prevent
  /// path traversal or other filesystem issues.
  static String _sanitizeFilename(String input) {
    return input.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
  }
}

/// Encodes [map] to JSON on a background isolate for bulk export.
String _encodeJsonMap(Map<String, Object?> map) {
  return jsonEncode(map);
}
