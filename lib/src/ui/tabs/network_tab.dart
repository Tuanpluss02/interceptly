import 'package:flutter/material.dart';
import 'package:netspecter/src/ui/netspecter_theme.dart';
import 'package:netspecter/src/ui/detail/request_detail_overlay.dart';
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
                  color: NetSpecterTheme.textMuted,
                  fontSize: 14,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: NetSpecterTheme.textMuted,
                  size: 20,
                ),
                filled: true,
                fillColor: NetSpecterTheme.surfaceContainer,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: const BorderSide(
                    color: NetSpecterTheme.indigo500,
                    width: 1.0,
                  ),
                ),
              ),
              style: const TextStyle(
                color: NetSpecterTheme.textSecondary,
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
                      style: TextStyle(color: NetSpecterTheme.textMuted),
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
                    
                    // Format time
                    final time = '${req.timestamp.hour.toString().padLeft(2, '0')}:${req.timestamp.minute.toString().padLeft(2, '0')}:${req.timestamp.second.toString().padLeft(2, '0')}';
                    final path = Uri.tryParse(req.url)?.path ?? req.url;

                    return _RequestLogItem(
                      method: req.method,
                      path: path,
                      time: time,
                      duration: '${req.durationMs}ms',
                      status: req.statusCode,
                      onTap: () {
                        // Open Detail Overlay with slide up transition
                        Navigator.of(context).push(PageRouteBuilder(
                          pageBuilder: (context, animation, secondaryAnimation) => RequestDetailOverlay(
                            entry: req,
                            session: session,
                          ),
                          transitionsBuilder: (context, animation, secondaryAnimation, child) {
                            const begin = Offset(0.0, 1.0);
                            const end = Offset.zero;
                            const curve = Curves.easeOutCubic;
                            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                            return SlideTransition(
                              position: animation.drive(tween),
                              child: child,
                            );
                          },
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
  final String path;
  final String time;
  final String duration;
  final int status;
  final VoidCallback onTap;

  const _RequestLogItem({
    required this.method,
    required this.path,
    required this.time,
    required this.duration,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final mStyle = NetSpecterTheme.getMethodStyle(method);
    final sStyle = NetSpecterTheme.getStatusStyle(status);

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
                    path,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: NetSpecterTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$time • $duration',
                    style: const TextStyle(
                      fontSize: 11,
                      color: NetSpecterTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Status Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              decoration: BoxDecoration(
                color: sStyle.bg,
                borderRadius: BorderRadius.circular(12.0),
              ),
              alignment: Alignment.center,
              child: Text(
                status.toString(),
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


