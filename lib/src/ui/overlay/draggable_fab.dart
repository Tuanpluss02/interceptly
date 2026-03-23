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
  });

  final Widget child;
  final Offset? initPosition;
  final double securityBottom;
  final double securityTop;

  @override
  State<DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<DraggableFab>
    with SingleTickerProviderStateMixin {
  Size _widgetSize = const Size(44, 44);
  final GlobalKey _childKey = GlobalKey();

  late final AnimationController _snapController;
  Animation<Offset>? _snapAnimation;
  late final ValueNotifier<Offset> _positionVN =
      ValueNotifier(Offset.zero);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _initPosition(context));
    _snapController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _snapController.addListener(() {
      if (_snapAnimation != null) {
        _positionVN.value = _snapAnimation!.value;
      }
    });
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  void _initPosition(BuildContext context) {
    final rb =
        _childKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb != null) _widgetSize = rb.size;

    final size = MediaQuery.of(context).size;
    final target = widget.initPosition ??
        Offset(size.width, size.height / 2); // default: right-center
    final snapped = _snapToEdge(target, size);
    _positionVN.value = snapped;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ValueListenableBuilder<Offset>(
          valueListenable: _positionVN,
          builder: (context, pos, _) {
            return Positioned(
              left: pos.dx,
              top: pos.dy,
              child: RepaintBoundary(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    _positionVN.value = Offset(
                      _positionVN.value.dx + details.delta.dx,
                      _positionVN.value.dy + details.delta.dy,
                    );
                  },
                  onPanEnd: (_) {
                    final size = MediaQuery.of(context).size;
                    final center = Offset(
                      pos.dx + _widgetSize.width / 2,
                      pos.dy + _widgetSize.height / 2,
                    );
                    final target = _snapToEdge(center, size);
                    _snapAnimation = Tween<Offset>(
                      begin: pos,
                      end: target,
                    ).animate(CurvedAnimation(
                      parent: _snapController,
                      curve: Curves.easeOutCubic,
                    ));
                    _snapController
                      ..reset()
                      ..forward();
                  },
                  child: KeyedSubtree(key: _childKey, child: widget.child),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// Snaps to the nearest left or right edge, clamping vertically within
  /// [securityTop] … [screenHeight - widgetHeight - securityBottom].
  Offset _snapToEdge(Offset center, Size screen) {
    final minTop = widget.securityTop;
    final maxTop =
        screen.height - _widgetSize.height - widget.securityBottom;

    final double left = center.dx < screen.width / 2
        ? 0
        : screen.width - _widgetSize.width;

    final double top = center.dy
        .clamp(minTop, maxTop.clamp(minTop, double.infinity));

    return Offset(left, top);
  }
}
