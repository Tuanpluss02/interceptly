import 'package:flutter/material.dart';

import '../interceptly_theme.dart';

class InterceptlyConfirmDialog extends StatelessWidget {
  const InterceptlyConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmText = 'Confirm',
    this.cancelText = 'Cancel',
  });

  final String title;
  final String message;
  final String confirmText;
  final String cancelText;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return InterceptlyConfirmDialog(
          title: title,
          message: message,
          confirmText: confirmText,
          cancelText: cancelText,
        );
      },
    );

    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: InterceptlyTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(InterceptlyTheme.radius.lg),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: InterceptlyTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(InterceptlyTheme.radius.lg),
          border: Border.all(color: InterceptlyTheme.dividerSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: InterceptlyTheme.typography.bodyMediumBold.copyWith(
                fontSize: 16,
                color: InterceptlyTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                color: InterceptlyTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: InterceptlyTheme.dividerSubtle),
                      minimumSize: const Size.fromHeight(40),
                    ),
                    child: Text(
                      cancelText,
                      style: InterceptlyTheme.typography.bodyMediumMedium
                          .copyWith(color: InterceptlyTheme.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                      backgroundColor: InterceptlyTheme.red500,
                      foregroundColor: InterceptlyGlobalColor.white,
                    ),
                    child: Text(
                      confirmText,
                      style: InterceptlyTheme.typography.bodyMediumMedium
                          .copyWith(color: InterceptlyGlobalColor.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
