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
    final embedded = widget.embedded;
    final Color tileColor = _isDesktop
        ? (embedded
            ? (widget.selected ? cs.primary.withOpacity(0.16) : Colors.transparent)
            : (widget.selected ? cs.primary.withOpacity(0.12) : cs.surface))
        : (embedded ? Colors.transparent : cs.surface);
    final Color bg = _isDesktop && !widget.selected && _hovered
        ? (embedded ? cs.primary.withOpacity(0.08) : cs.surface.withOpacity(0.9))
        : tileColor;
    final content = MouseRegion(
      onEnter: (_) { if (_isDesktop) setState(() => _hovered = true); },
      onExit: (_) { if (_isDesktop) setState(() => _hovered = false); },
      cursor: _isDesktop ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: SizedBox(
        width: double.infinity,
        child: IosCardPress(
          baseColor: bg,
          borderRadius: BorderRadius.circular(16),
          haptics: false,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          padding: EdgeInsets.fromLTRB(_isDesktop ? 12 : 4, 6, 12, 6),
          child: Row(
            children: [
              widget.avatar,
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: _isDesktop ? 14 : 15, fontWeight: FontWeight.w600, color: widget.textColor),
                ),
              ),
              if (!_isDesktop) ...[
                const SizedBox(width: 8),
                IosIconButton(
                  icon: Lucide.Pencil,
                  size: 18,
                  color: cs.onSurface.withOpacity(0.7),
                  padding: const EdgeInsets.all(8),
                  minSize: 36,
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
