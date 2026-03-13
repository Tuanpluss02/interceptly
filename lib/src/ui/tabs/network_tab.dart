import 'package:flutter/material.dart';
import 'package:netspecter/src/ui/netspecter_theme.dart';
import 'package:netspecter/src/ui/detail/request_detail_overlay.dart';

class NetworkTab extends StatelessWidget {
  const NetworkTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Search & Filters
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search URLs...',
                hintStyle: const TextStyle(color: NetSpecterTheme.textMuted, fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: NetSpecterTheme.textMuted, size: 20),
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
                  borderSide: const BorderSide(color: NetSpecterTheme.indigo500, width: 1.0),
                ),
              ),
              style: const TextStyle(color: NetSpecterTheme.textSecondary, fontSize: 14),
            ),
          ),
          
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
          
          // Request List
          Expanded(
            child: ListView.separated(
              itemCount: _mockRequests.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: Colors.white.withValues(alpha: 0.05),
              ),
              itemBuilder: (context, index) {
                final req = _mockRequests[index];
                return _RequestLogItem(
                  method: req['method'] as String,
                  path: req['path'] as String,
                  time: req['time'] as String,
                  duration: req['duration'] as String,
                  status: req['status'] as int,
                  onTap: () {
                    // Open Detail Overlay with slide up transition
                    Navigator.of(context).push(PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) => RequestDetailOverlay(request: req),
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

// Mock Data matching ui.html
const _mockRequests = [
  {
    'id': 1, 'method': 'GET', 'path': '/api/v1/users/profile',
    'status': 200, 'time': '14:05:22', 'duration': '120ms',
  },
  {
    'id': 2, 'method': 'POST', 'path': '/api/v1/auth/login',
    'status': 201, 'time': '14:04:10', 'duration': '350ms',
  },
  {
    'id': 3, 'method': 'GET', 'path': '/api/v1/products?limit=10',
    'status': 404, 'time': '14:00:15', 'duration': '85ms',
  },
  {
    'id': 4, 'method': 'DELETE', 'path': '/api/v1/cart/items/12',
    'status': 500, 'time': '13:55:02', 'duration': '1200ms',
  },
  {
    'id': 5, 'method': 'WS', 'path': 'wss://chat.server.com/socket',
    'status': 101, 'time': '13:50:00', 'duration': 'Active',
  }
];
