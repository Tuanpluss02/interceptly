import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/detail/request_detail_page.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/utils/error_summary.dart';
import 'package:interceptly/src/ui/widgets/interceptly_text_field.dart';

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
            child: InterceptlySearchField(
              hintText: 'Search URL, headers, body…',
              onChanged: (value) {
                final q = value.trim();
                if (q.isEmpty) {
                  session.cancelMasterSearch();
                } else {
                  session.startMasterSearch(q);
                }
              },
            ),
          ),

          Divider(
            height: 1,
            color: InterceptlyTheme.dividerSubtle,
          ),

          // Request List
          Expanded(
            child: AnimatedBuilder(
              animation: session,
              builder: (context, _) {
                final entries = session.entries;

                if (entries.isEmpty) {
                  return Center(
                    child: Text(
                      'No network requests yet.',
                      style: InterceptlyTheme.typography.bodyMediumRegular
                          .copyWith(color: InterceptlyTheme.textMuted),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: InterceptlyTheme.dividerSubtle,
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
        ? const StatusStyle(
            bg: InterceptlyTheme.red500,
            text: InterceptlyGlobalColor.white,
          )
        : InterceptlyTheme.getStatusStyle(status);

    return InkWell(
      onTap: onTap,
      hoverColor: InterceptlyTheme.hoverOverlay,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            // Method Badge
            Container(
              width: 48,
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              decoration: BoxDecoration(
                color: mStyle.bg.withValues(alpha: 0.22),
                border: Border.all(color: mStyle.border.withValues(alpha: 0.8)),
                borderRadius: BorderRadius.circular(6.0),
              ),
              alignment: Alignment.center,
              child: Text(
                method,
                style: InterceptlyTheme.typography.labelSmallMedium.copyWith(
                  color: mStyle.text,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
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
                    style:
                        InterceptlyTheme.typography.bodyMediumMedium.copyWith(
                      fontSize: 13,
                      color: InterceptlyTheme.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$time • $duration',
                    style:
                        InterceptlyTheme.typography.bodyMediumRegular.copyWith(
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
                      style:
                          InterceptlyTheme.typography.bodyMediumBold.copyWith(
                        fontSize: 11,
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
