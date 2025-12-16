import 'package:flutter/material.dart';

/// A draggable handle for resizing the sidebar width on desktop.
/// Used in tablet/desktop layout for adjusting the left sidebar width.
class SidebarResizeHandle extends StatefulWidget {
  const SidebarResizeHandle({
    super.key,
    required this.visible,
    required this.onDrag,
    this.onDragEnd,
  });

  final bool visible;
  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;

  @override
  State<SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<SidebarResizeHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!widget.visible) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
      onHorizontalDragEnd: (_) => widget.onDragEnd?.call(),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Container(
          width: 4,
          height: double.infinity,
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Container(
            width: 1,
            height: double.infinity,
            color: _hovered
                ? cs.primary.withOpacity(0.28)
                : cs.outlineVariant.withOpacity(0.10),
          ),
        ),
      ),
    );
  }
}
