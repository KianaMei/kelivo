import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';

/// Show a desktop-only floating popover above a widget.
/// Appears with blurred glass background, slides up from anchor, and dismisses on outside tap.
/// Automatically adapts to anchor position/size changes (e.g., window resize).
/// Returns a callback that can be used to programmatically close the popover.
Future<VoidCallback> showDesktopPopover(
  BuildContext context, {
  required GlobalKey anchorKey,
  required Widget child,
  double? width,
  double? maxHeight,
  BorderRadius? borderRadius,
}) async {
  final overlay = Overlay.of(context);
  if (overlay == null) return () {};

  late OverlayEntry entry;
  bool closed = false;

  void closePopover() {
    if (closed) return;
    closed = true;
    try {
      entry.remove();
    } catch (_) {}
  }

  entry = OverlayEntry(
    builder: (ctx) => _PopoverOverlay(
      anchorKey: anchorKey,
      width: width,
      maxHeight: maxHeight,
      borderRadius: borderRadius,
      onClose: closePopover,
      child: child,
    ),
  );
  overlay.insert(entry);

  return closePopover;
}

class _PopoverOverlay extends StatefulWidget {
  const _PopoverOverlay({
    required this.anchorKey,
    required this.onClose,
    required this.child,
    this.width,
    this.maxHeight,
    this.borderRadius,
  });

  final GlobalKey anchorKey;
  final VoidCallback onClose;
  final Widget child;
  final double? width;
  final double? maxHeight;
  final BorderRadius? borderRadius;

  @override
  State<_PopoverOverlay> createState() => _PopoverOverlayState();
}

class _PopoverOverlayState extends State<_PopoverOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  bool _closing = false;
  Offset _offset = const Offset(0, 0.12); // Start slightly below
  Rect? _lastAnchorRect;
  Timer? _monitorTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    // Slide up into place
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() => _offset = Offset.zero);
      try {
        await _controller.forward();
      } catch (_) {}
    });

    // Start monitoring anchor position/size changes
    _startMonitoring();
  }

  void _startMonitoring() {
    // Check anchor position/size every frame (60fps)
    _monitorTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || _closing) return;

      final keyContext = widget.anchorKey.currentContext;
      if (keyContext == null) return;

      final box = keyContext.findRenderObject() as RenderBox?;
      if (box == null) return;

      final offset = box.localToGlobal(Offset.zero);
      final size = box.size;
      final currentRect = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);

      // Check if anchor moved or resized
      if (_lastAnchorRect != currentRect) {
        _lastAnchorRect = currentRect;
        if (mounted) {
          setState(() {}); // Trigger rebuild with new position
        }
      }
    });
  }

  @override
  void dispose() {
    _monitorTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    // Slide down and fade out
    setState(() => _offset = const Offset(0, 1.0));
    try {
      await _controller.reverse();
    } catch (_) {}
    if (mounted) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;

    // Get anchor position/size in real-time (adapts to window resize)
    final keyContext = widget.anchorKey.currentContext;
    if (keyContext == null) {
      // Anchor not available, close popover
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onClose());
      return const SizedBox.shrink();
    }

    final box = keyContext.findRenderObject() as RenderBox?;
    if (box == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onClose());
      return const SizedBox.shrink();
    }

    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    final anchorRect = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);

    // Calculate width: slightly narrower than anchor (like remote does)
    final width = widget.width ?? (size.width - 16).clamp(260.0, 720.0);
    final left = (anchorRect.left + (anchorRect.width - width) / 2)
        .clamp(8.0, screen.width - width - 8.0);
    final clipHeight = anchorRect.top.clamp(0.0, screen.height);

    return Stack(
      children: [
        // Transparent barrier
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _close,
          ),
        ),
        // Popover panel (clipped to only show above anchor)
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: clipHeight,
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: left,
                  width: width,
                  bottom: 0,
                  child: FadeTransition(
                    opacity: _fadeIn,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      offset: _offset,
                      child: GlassPanel(
                        borderRadius: widget.borderRadius ??
                            const BorderRadius.vertical(top: Radius.circular(14)),
                        child: widget.maxHeight != null
                            ? ConstrainedBox(
                                constraints: BoxConstraints(maxHeight: widget.maxHeight!),
                                child: widget.child,
                              )
                            : widget.child,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Glass panel with blur and translucent background
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.borderRadius});
  final Widget child;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (isDark ? Colors.black : Colors.white)
                .withOpacity(isDark ? 0.28 : 0.56),
            border: Border(
              top: BorderSide(
                  color: Colors.white.withOpacity(isDark ? 0.06 : 0.18),
                  width: 0.7),
              left: BorderSide(
                  color: Colors.white.withOpacity(isDark ? 0.04 : 0.12),
                  width: 0.6),
              right: BorderSide(
                  color: Colors.white.withOpacity(isDark ? 0.04 : 0.12),
                  width: 0.6),
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Reusable row item for popover lists
class PopoverRowItem extends StatefulWidget {
  const PopoverRowItem({
    super.key,
    required this.leading,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final Widget leading;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<PopoverRowItem> createState() => _PopoverRowItemState();
}

class _PopoverRowItemState extends State<PopoverRowItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final onColor = widget.selected ? cs.primary : cs.onSurface;
    final hoverBg = (isDark ? Colors.white : Colors.black)
        .withOpacity(isDark ? 0.12 : 0.10);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hovered ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Center(child: widget.leading),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.none,
                  ).copyWith(color: onColor),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: widget.selected
                    ? Icon(Icons.check,
                        key: const ValueKey('check'), size: 16, color: cs.primary)
                    : const SizedBox(width: 16, key: ValueKey('space')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
