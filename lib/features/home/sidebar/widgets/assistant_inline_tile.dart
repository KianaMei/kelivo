import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import '../../../../icons/lucide_adapter.dart';
import '../../../../shared/widgets/ios_tactile.dart';

/// Inline assistant tile for sidebar
class AssistantInlineTile extends StatefulWidget {
  const AssistantInlineTile({
    super.key,
    required this.avatar,
    required this.name,
    required this.textColor,
    required this.embedded,
    required this.onTap,
    required this.onEditTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.selected = false,
  });

  final Widget avatar;
  final String name;
  final Color textColor;
  final bool embedded;
  final VoidCallback onTap;
  final VoidCallback onEditTap;
  final VoidCallback? onLongPress;
  final void Function(Offset globalPosition)? onSecondaryTapDown;
  final bool selected;

  @override
  State<AssistantInlineTile> createState() => _AssistantInlineTileState();
}

class _AssistantInlineTileState extends State<AssistantInlineTile> {
  bool _hovered = false;
  bool get _isDesktop => defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 背景色：选中时有颜色，否则透明
    final Color bg = widget.selected
        ? cs.primary.withOpacity(isDark ? 0.18 : 0.1)
        : (_hovered && _isDesktop
            ? cs.primary.withOpacity(isDark ? 0.08 : 0.05)
            : Colors.transparent);
    
    final content = MouseRegion(
      onEnter: (_) { if (_isDesktop) setState(() => _hovered = true); },
      onExit: (_) { if (_isDesktop) setState(() => _hovered = false); },
      cursor: _isDesktop ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              widget.avatar,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: widget.textColor,
                    height: 1.3,
                  ),
                ),
              ),
              if (!_isDesktop) ...[
                const SizedBox(width: 6),
                IosIconButton(
                  icon: Lucide.Pencil,
                  size: 16,
                  color: cs.onSurface.withOpacity(0.5),
                  padding: const EdgeInsets.all(6),
                  minSize: 32,
                  onTap: widget.onEditTap,
                  semanticLabel: 'Edit assistant',
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: widget.onSecondaryTapDown == null
          ? null
          : (details) => widget.onSecondaryTapDown!(details.globalPosition),
      child: content,
    );
  }
}
