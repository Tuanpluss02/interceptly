import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../export/curl_generator.dart';
import '../../export/har_exporter.dart';
import '../../model/request_record.dart';
import '../netspecter_theme.dart';

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
      backgroundColor: NetSpecterTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: NetSpecterTheme.indigo500),
              title: const Text('Copy cURL'),
              subtitle: const Text('Copy request as cURL command',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(context);
                shareCurlCommand(record);
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading:
                  const Icon(Icons.download, color: NetSpecterTheme.indigo500),
              title: const Text('Export HAR'),
              subtitle: const Text('Download HAR file',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(context);
                exportHarFile(record);
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
      _getSharePositionOrigin().then((origin) {
        Share.share(
          curl,
          subject: 'cURL Command',
          sharePositionOrigin: origin,
        );
      });
    } catch (e) {
      _showError('Error: $e');
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
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'HAR Export',
        text: 'Network request HAR export',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      _showError('Error exporting HAR: $e');
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

  void _showError(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
