import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/utils/error_summary.dart';

import '../../storage/inspector_session.dart';

class NetworkTab extends StatelessWidget {
  const NetworkTab({super.key, required this.session});

  final InspectorSession session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Search & Filters
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: (value) {
                final q = value.trim();
                if (q.isEmpty) {
                  session.cancelMasterSearch();
                } else {
                  session.startMasterSearch(q);
                }
              },
              decoration: InputDecoration(
                hintText: 'Search URL, headers, body…',
                hintStyle: const TextStyle(
                  color: InterceptlyTheme.textMuted,
                  fontSize: 14,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: InterceptlyTheme.textMuted,
                  size: 20,
                ),
                filled: true,
                fillColor: InterceptlyTheme.surfaceContainer,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: const BorderSide(
                    color: InterceptlyTheme.indigo500,
                    width: 1.0,
                  ),
                ),
              ),
              style: const TextStyle(
                color: InterceptlyTheme.textSecondary,
                fontSize: 14,
              ),
            ),
          ),

          Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),

          // Request List
          Expanded(
            child: AnimatedBuilder(
              animation: session,
              builder: (context, _) {
                final entries = session.entries;

                if (entries.isEmpty) {
                  return const Center(
                    child: Text(
                      'No network requests yet.',
                      style: TextStyle(color: InterceptlyTheme.textMuted),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                  itemBuilder: (context, index) {
                    final req = entries[index];
                    final isPending = req.statusCode == 0 && !req.hasError;
                    final isErrorWithoutStatus =
                        req.statusCode == 0 && req.hasError;
                    final shortError = summarizeRequestError(
                      errorType: req.errorType,
                      errorMessage: req.errorMessage,
                    );

                    // Format time
                    final time =
                        '${req.timestamp.hour.toString().padLeft(2, '0')}:${req.timestamp.minute.toString().padLeft(2, '0')}:${req.timestamp.second.toString().padLeft(2, '0')}';
                    String displayUrl = req.url;
                    if (session.urlDecodeEnabled) {
                      try {
                        displayUrl = Uri.decodeFull(req.url);
                      } catch (_) {}
                    }

                    return _RequestLogItem(
                      method: req.method,
                      url: displayUrl,
                      time: time,
                      duration: isPending
                          ? 'loading…'
                          : isErrorWithoutStatus
                              ? shortError
                              : '${req.durationMs}ms',
                      status: req.statusCode,
                      hasError: req.hasError,
                      isPending: isPending,
                      onTap: () {
                        // Open Detail Page
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) => RequestDetailPage(
                            entry: req,
                            session: session,
                          ),
                        ));
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestLogItem extends StatelessWidget {
  final String method;
  final String url;
  final String time;
  final String duration;
  final int status;
  final bool hasError;
  final bool isPending;
  final VoidCallback onTap;

  const _RequestLogItem({
    required this.method,
    required this.url,
    required this.time,
    required this.duration,
    required this.status,
    required this.hasError,
    required this.isPending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final mStyle = InterceptlyTheme.getMethodStyle(method);
    final isErrorWithoutStatus = status == 0 && hasError;
    final sStyle = isErrorWithoutStatus
        ? const StatusStyle(bg: InterceptlyTheme.red500, text: Colors.white)
        : InterceptlyTheme.getStatusStyle(status);

    return InkWell(
      onTap: onTap,
      hoverColor: Colors.white.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            // Method Badge
            Container(
              width: 48,
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              decoration: BoxDecoration(
                color: mStyle.bg,
                border: Border.all(color: mStyle.border),
                borderRadius: BorderRadius.circular(6.0),
              ),
              alignment: Alignment.center,
              child: Text(
                method,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: mStyle.text,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Middle Content (Path & Time)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    url,
                    style: const TextStyle(
                      fontFamily: InterceptlyTheme.fontFamily,
                      package: InterceptlyTheme.fontPackage,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: InterceptlyTheme.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$time • $duration',
                    style: const TextStyle(
                      fontSize: 11,
                      color: InterceptlyTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Status Badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              decoration: BoxDecoration(
                color: sStyle.bg,
                borderRadius: BorderRadius.circular(12.0),
              ),
              alignment: Alignment.center,
              child: isPending
                  ? SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        valueColor: AlwaysStoppedAnimation<Color>(sStyle.text),
                      ),
                    )
                  : Text(
                      isErrorWithoutStatus ? 'ERR' : status.toString(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: sStyle.text,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
