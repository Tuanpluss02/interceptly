import 'package:flutter/material.dart';

/// A draggable FAB that always snaps to the left or right edge of the screen.
///
/// The button can be dragged anywhere but on release it snaps to whichever
/// vertical edge is closest. Top and bottom edges are excluded — the button
/// stays within the vertical bounds defined by [securityTop] and
/// [securityBottom].
class DraggableFab extends StatefulWidget {
  const DraggableFab({
    required this.child,
    super.key,
    this.initPosition,
    this.securityBottom = 0,
    this.securityTop = 0,
    this.positionNotifier,
  });

  final Widget child;
  final Offset? initPosition;
  final double securityBottom;
  final double securityTop;
  final ValueNotifier<Offset?>? positionNotifier;

  @override
  State<DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<DraggableFab>
    with SingleTickerProviderStateMixin {
  Size _widgetSize = const Size(48, 48);
  final GlobalKey _childKey = GlobalKey();

  late final AnimationController _snapController;
  Animation<Offset>? _snapAnimation;
  late final ValueNotifier<Offset> _positionVN;

  bool _isInitialized = false;
  bool _isRightEdge = true;
  double _relativeY = 0.5;
  Size? _lastParentSize;

  @override
  void initState() {
    super.initState();
    _positionVN = ValueNotifier(
      widget.positionNotifier?.value ?? widget.initPosition ?? Offset.zero,
    );
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _snapController.addListener(() {
      if (_snapAnimation != null) {
        _positionVN.value = _snapAnimation!.value;
        widget.positionNotifier?.value = _snapAnimation!.value;
      }
    });
  }

  @override
  void didUpdateWidget(DraggableFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.securityTop != widget.securityTop ||
        oldWidget.securityBottom != widget.securityBottom) {
      if (_lastParentSize != null && _isInitialized) {
        _adjustPositionToSize(_lastParentSize!);
      }
    }
  }

  @override
  void dispose() {
    _snapController.dispose();
    _positionVN.dispose();
    super.dispose();
  }

  void _updateWidgetSize() {
    final rb = _childKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb != null && rb.hasSize && rb.size.width > 0 && rb.size.height > 0) {
      _widgetSize = rb.size;
    }
  }

  void _adjustPositionToSize(Size newSize) {
    if (newSize.width <= 0 || newSize.height <= 0) return;
    _updateWidgetSize();

    final minTop = widget.securityTop;
    final maxTop = (newSize.height - _widgetSize.height - widget.securityBottom)
        .clamp(minTop, double.infinity);

    final double left = _isRightEdge
        ? (newSize.width - _widgetSize.width).clamp(0.0, double.infinity)
        : 0.0;

    final double top = (newSize.height * _relativeY - _widgetSize.height / 2)
        .clamp(minTop, maxTop);

    _positionVN.value = Offset(left, top);
    widget.positionNotifier?.value = Offset(left, top);
  }

  void _snapToEdgeWithAnimation(Size size) {
    _updateWidgetSize();
    final pos = _positionVN.value;
    final center = Offset(
      pos.dx + _widgetSize.width / 2,
      pos.dy + _widgetSize.height / 2,
    );
    final target = _snapToEdge(center, size);

    _isRightEdge = target.dx >= (size.width / 2);
    if (size.height > 0) {
      _relativeY =
          ((target.dy + _widgetSize.height / 2) / size.height).clamp(0.0, 1.0);
    }

    _snapAnimation = Tween<Offset>(begin: pos, end: target).animate(
      CurvedAnimation(
        parent: _snapController,
        curve: Curves.easeOutCubic,
      ),
    );
    _snapController
      ..reset()
      ..forward();
  }

  Offset _snapToEdge(Offset center, Size screen) {
    final minTop = widget.securityTop;
    final maxTop = (screen.height - _widgetSize.height - widget.securityBottom)
        .clamp(minTop, double.infinity);

    final double left = center.dx < screen.width / 2
        ? 0.0
        : (screen.width - _widgetSize.width).clamp(0.0, double.infinity);

    final double top = center.dy.clamp(minTop, maxTop);

    return Offset(left, top);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final parentSize = Size(constraints.maxWidth, constraints.maxHeight);

        if (parentSize.width <= 0 || parentSize.height <= 0) {
          return const SizedBox.shrink();
        }

        if (!_isInitialized) {
          _isInitialized = true;
          _lastParentSize = parentSize;
          final savedPos = widget.positionNotifier?.value;
          final target = savedPos ??
              widget.initPosition ??
              Offset(parentSize.width, parentSize.height / 2);

          if (savedPos != null) {
            _isRightEdge = savedPos.dx >= (parentSize.width / 2);
            _relativeY = parentSize.height > 0
                ? ((savedPos.dy + _widgetSize.height / 2) / parentSize.height)
                    .clamp(0.0, 1.0)
                : 0.5;
            _positionVN.value = savedPos;
          } else {
            _isRightEdge = target.dx >= (parentSize.width / 2);
            _relativeY = parentSize.height > 0
                ? (target.dy / parentSize.height).clamp(0.0, 1.0)
                : 0.5;
            _positionVN.value = _snapToEdge(target, parentSize);
            widget.positionNotifier?.value = _positionVN.value;
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _updateWidgetSize();
            if (savedPos != null) {
              _relativeY = parentSize.height > 0
                  ? ((savedPos.dy + _widgetSize.height / 2) / parentSize.height)
                      .clamp(0.0, 1.0)
                  : 0.5;
            } else {
              _adjustPositionToSize(parentSize);
            }
          });
        } else if (_lastParentSize != null &&
            (_lastParentSize!.width != parentSize.width ||
                _lastParentSize!.height != parentSize.height)) {
          _lastParentSize = parentSize;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _adjustPositionToSize(parentSize);
          });
        }

        return Stack(
          children: [
            ValueListenableBuilder<Offset>(
              valueListenable: _positionVN,
              builder: (context, pos, _) {
                final minTop = widget.securityTop;
                final maxTop = (parentSize.height -
                        _widgetSize.height -
                        widget.securityBottom)
                    .clamp(minTop, double.infinity);
                final clampedX = pos.dx.clamp(
                  0.0,
                  (parentSize.width - _widgetSize.width)
                      .clamp(0.0, double.infinity),
                );
                final clampedY = pos.dy.clamp(minTop, maxTop);

                return Positioned(
                  left: clampedX,
                  top: clampedY,
                  child: RepaintBoundary(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) {
                        final newPos = Offset(
                          _positionVN.value.dx + details.delta.dx,
                          _positionVN.value.dy + details.delta.dy,
                        );
                        _positionVN.value = newPos;
                        widget.positionNotifier?.value = newPos;
                      },
                      onPanEnd: (_) {
                        _snapToEdgeWithAnimation(parentSize);
                      },
                      onPanCancel: () {
                        _snapToEdgeWithAnimation(parentSize);
                      },
                      child: KeyedSubtree(key: _childKey, child: widget.child),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
