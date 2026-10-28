import 'dart:async';

import 'package:flutter/material.dart';

import '../interceptly_theme.dart';

/// Singleton toast overlay with queue replacement and disposal.
///
/// Only one toast is visible at a time. Each [show] call replaces the
/// previous entry and restarts the dismiss timer, preventing stacked
/// overlays during rapid replay or export feedback.
class ToastNotification extends StatefulWidget {
  final String message;

  const ToastNotification({super.key, required this.message});

  /// Set the navigator key globally so toast can be shown without context
  static GlobalKey<NavigatorState>? _navigatorKey;

  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// Removes any visible toast and cancels its dismiss timer.
  static void dispose() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    try {
      _currentEntry?.remove();
    } catch (_) {}
    try {
      _currentEntry?.dispose();
    } catch (_) {}
    _currentEntry = null;
  }

  static void show(String message, {BuildContext? contextHint}) {
    BuildContext? context = contextHint ?? _navigatorKey?.currentContext;
    if (context == null) {
      debugPrint('ToastNotification: no context available');
      return;
    }

    try {
      dispose();
      final overlayState = Overlay.of(context, rootOverlay: true);
      final overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          bottom: 80.0,
          left: 0,
          right: 0,
          child: ToastNotification(message: message),
        ),
      );
      _currentEntry = overlayEntry;

      overlayState.insert(overlayEntry);

      _dismissTimer = Timer(const Duration(seconds: 2), () {
        if (overlayEntry.mounted) {
          overlayEntry.remove();
        }
        if (identical(_currentEntry, overlayEntry)) {
          _currentEntry = null;
        }
      });
    } catch (e) {
      debugPrint('ToastNotification error: $e');
    }
  }

  @override
  State<ToastNotification> createState() => _ToastNotificationState();
}

class _ToastNotificationState extends State<ToastNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 1700), () {
      if (mounted) {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: InterceptlyTheme.themeData(context: context),
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _opacityAnimation,
          child: Center(
            child: Material(
              color: InterceptlyGlobalColor.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                decoration: BoxDecoration(
                  color: InterceptlyGlobalColor.white,
                  borderRadius: BorderRadius.circular(20.0),
                  boxShadow: [
                    BoxShadow(
                      color:
                          InterceptlyGlobalColor.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  widget.message,
                  style: InterceptlyTheme.typography.bodyMediumMedium.copyWith(
                    color: InterceptlyGlobalColor.black,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
