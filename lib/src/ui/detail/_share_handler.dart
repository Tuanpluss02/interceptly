import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../export/curl_generator.dart';
import '../../export/har_exporter.dart';
import '../../export/postman_exporter.dart';
import '../../model/request_record.dart';
import '../interceptly_theme.dart';
import '../widgets/toast_notification.dart';

class ShareHandler {
  final BuildContext context;
  final GlobalKey fabKey;

  const ShareHandler({
    required this.context,
    required this.fabKey,
  });

  void showShareMenu(RequestRecord record) {
    showModalBottomSheet(
      context: context,
      backgroundColor: InterceptlyTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
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
                    style: InterceptlyTheme.typography.bodyMediumBold.copyWith(
                      color: InterceptlyTheme.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading:
                  const Icon(Icons.copy, color: InterceptlyTheme.indigo500),
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
              leading:
                  const Icon(Icons.download, color: InterceptlyTheme.indigo500),
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
              leading: const Icon(Icons.upload_file,
                  color: InterceptlyTheme.indigo500),
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
    try {
      final collectionData = PostmanExporter.fromRecords(records);
      final collectionJson = jsonEncode(collectionData);

      final directory = await getTemporaryDirectory();
      final fileName =
          'interceptly_${DateTime.now().millisecondsSinceEpoch}.postman_collection.json';
      final file = File('${directory.path}/$fileName');

      await file.writeAsString(collectionJson);

      final origin = await _getSharePositionOrigin();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Postman Collection Export',
          text: 'Postman Collection export from Interceptly',
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      ToastNotification.show('Error exporting Postman collection: $e');
    }
  }

  void exportHarFile(RequestRecord record) async {
    try {
      final harData = HarExporter.fromRecords([record]);
      final harJson = jsonEncode(harData);

      // Save to temp directory (system will auto-clean)
      final directory = await getTemporaryDirectory();
      final sanitizedMethod = _sanitizeFilename(record.method);
      final fileName =
          'request_${sanitizedMethod}_${DateTime.now().millisecondsSinceEpoch}.har';
      final file = File('${directory.path}/$fileName');

      await file.writeAsString(harJson);

      // Share file using system share UI
      final origin = await _getSharePositionOrigin();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'HAR Export',
          text: 'Network request HAR export',
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      ToastNotification.show('Error exporting HAR: $e');
    }
  }

  Future<Rect> _getSharePositionOrigin() async {
    try {
      final box = fabKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        final offset = box.localToGlobal(Offset.zero);
        final size = box.size;
        return Rect.fromLTWH(
          offset.dx,
          offset.dy,
          size.width,
          size.height,
        );
      }
    } catch (e) {
      // Ignore, will use default
    }
    // Fallback: center of screen
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
