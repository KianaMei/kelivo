import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Shows a confirmation popover near the trigger element.
/// Returns true if confirmed, false if cancelled or dismissed.
///
/// Usage:
/// ```dart
/// final anchorKey = GlobalKey();
/// // In your widget:
/// IconButton(
///   key: anchorKey,
///   icon: Icon(Icons.delete),
///   onPressed: () async {
///     final confirmed = await showPopConfirm(
///       context,
///       anchorKey: anchorKey,
///       title: '确定删除？',
///     );
///     if (confirmed) { /* do delete */ }
///   },
/// )
/// ```
Future<bool> showPopConfirm(
  BuildContext context, {
  required GlobalKey anchorKey,
  required String title,
  String? subtitle,
  String confirmText = '确认',
  String cancelText = '取消',
  bool danger = true,
  IconData? icon,
}) async {
  final overlay = Overlay.of(context);
  if (overlay == null) return false;

  final completer = ValueNotifier<bool?>(null);
  late OverlayEntry entry;
  bool closed = false;

  void close(bool result) {
    if (closed) return;
    closed = true;
    completer.value = result;
    try {
      entry.remove();
    } catch (_) {}
  }

  entry = OverlayEntry(
    builder: (ctx) => _PopConfirmOverlay(
      anchorKey: anchorKey,
      title: title,
      subtitle: subtitle,
      confirmText: confirmText,
      cancelText: cancelText,
      danger: danger,
      icon: icon,
      onConfirm: () => close(true),
      onCancel: () => close(false),
    ),
  );

  overlay.insert(entry);

  // Wait for user action
  while (completer.value == null) {
    await Future.delayed(const Duration(milliseconds: 16));
  }

  return completer.value ?? false;
}

class _PopConfirmOverlay extends StatefulWidget {
  const _PopConfirmOverlay({
    required this.anchorKey,
    required this.title,
    required this.confirmText,
    required this.cancelText,
    required this.danger,
    required this.onConfirm,
    required this.onCancel,
    this.subtitle,
    this.icon,
  });

  final GlobalKey anchorKey;
  final String title;
  final String? subtitle;
  final String confirmText;
  final String cancelText;
  final bool danger;
  final IconData? icon;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  State<_PopConfirmOverlay> createState() => _PopConfirmOverlayState();
}

class _PopConfirmOverlayState extends State<_PopConfirmOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss(bool confirmed) async {
    await _controller.reverse();
    if (confirmed) {
      widget.onConfirm();
    } else {
      widget.onCancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Get anchor position
    final keyContext = widget.anchorKey.currentContext;
    if (keyContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onCancel());
      return const SizedBox.shrink();
    }

    final box = keyContext.findRenderObject() as RenderBox?;
    if (box == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onCancel());
      return const SizedBox.shrink();
    }

    final anchorPos = box.localToGlobal(Offset.zero);
    final anchorSize = box.size;
    final anchorCenter = anchorPos.dx + anchorSize.width / 2;

    // Popover dimensions
    const popWidth = 220.0;
    const popHeight = 100.0; // Approximate height

    // Determine if popover should appear above or below
    final spaceBelow = screen.height - anchorPos.dy - anchorSize.height;
    final spaceAbove = anchorPos.dy;
    final showBelow = spaceBelow >= popHeight + 8 || spaceBelow > spaceAbove;

    // Calculate horizontal position (centered on anchor, clamped to screen)
    final left = (anchorCenter - popWidth / 2).clamp(8.0, screen.width - popWidth - 8);

    // Calculate vertical position
    final double top;
    final double? bottom;
    if (showBelow) {
      top = anchorPos.dy + anchorSize.height + 6;
      bottom = null;
    } else {
      top = 0;
      bottom = screen.height - anchorPos.dy + 6;
    }

    return Stack(
      children: [
        // Barrier (transparent, dismisses on tap)
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _dismiss(false),
          ),
        ),
        // Popover
        Positioned(
          left: left,
          top: showBelow ? top : null,
          bottom: showBelow ? null : bottom,
          width: popWidth,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              alignment: showBelow ? Alignment.topCenter : Alignment.bottomCenter,
              child: _buildPopover(cs, isDark),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPopover(ColorScheme cs, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF1E1E1E) : Colors.white)
                .withOpacity(isDark ? 0.92 : 0.96),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.4 : 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row
                  Row(
                    children: [
                      if (widget.icon != null) ...[
                        Icon(
                          widget.icon,
                          size: 18,
                          color: widget.danger ? cs.error : cs.primary,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Subtitle
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Cancel button
                      _PopConfirmButton(
                        label: widget.cancelText,
                        onTap: () => _dismiss(false),
                        isPrimary: false,
                        isDanger: false,
                      ),
                      const SizedBox(width: 8),
                      // Confirm button
                      _PopConfirmButton(
                        label: widget.confirmText,
                        onTap: () => _dismiss(true),
                        isPrimary: true,
                        isDanger: widget.danger,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PopConfirmButton extends StatefulWidget {
  const _PopConfirmButton({
    required this.label,
    required this.onTap,
    required this.isPrimary,
    required this.isDanger,
  });

  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool isDanger;

  @override
  State<_PopConfirmButton> createState() => _PopConfirmButtonState();
}

class _PopConfirmButtonState extends State<_PopConfirmButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    Color bgColor;
    Color textColor;

    if (widget.isPrimary) {
      if (widget.isDanger) {
        bgColor = _pressed
            ? cs.error.withOpacity(0.9)
            : _hovered
                ? cs.error.withOpacity(0.85)
                : cs.error;
        textColor = cs.onError;
      } else {
        bgColor = _pressed
            ? cs.primary.withOpacity(0.9)
            : _hovered
                ? cs.primary.withOpacity(0.85)
                : cs.primary;
        textColor = cs.onPrimary;
      }
    } else {
      bgColor = _pressed
          ? (isDark ? Colors.white12 : Colors.black12)
          : _hovered
              ? (isDark ? Colors.white10 : Colors.black.withOpacity(0.05))
              : Colors.transparent;
      textColor = cs.onSurface.withOpacity(0.8);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: widget.isPrimary
                ? null
                : Border.all(
                    color: cs.onSurface.withOpacity(0.12),
                    width: 0.5,
                  ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
