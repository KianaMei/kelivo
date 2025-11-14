import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../icons/lucide_adapter.dart';

class AssistantInlineTile extends StatelessWidget {
  const AssistantInlineTile({
    required this.avatar,
    required this.name,
    required this.textColor,
    required this.embedded,
    required this.selected,
    required this.onTap,
    required this.onEditTap,
    required this.onLongPress,
    required this.onSecondaryTapDown,
  });

  final Widget avatar;
  final String name;
  final Color textColor;
  final bool embedded;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEditTap;
  final VoidCallback onLongPress;
  final void Function(Offset globalPosition) onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Listener(
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kSecondaryMouseButton) {
          onSecondaryTapDown(event.position);
        }
      },
      child: IosCardPress(
        baseColor: embedded ? Colors.transparent : cs.surface,
        borderRadius: BorderRadius.circular(16),
        haptics: false,
        onTap: onTap,
        onLongPress: onLongPress,
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
            IosIconButton(
              size: 18,
              color: textColor.withOpacity(0.7),
              icon: Lucide.Pencil,
              padding: const EdgeInsets.all(8),
              onTap: onEditTap,
            ),
          ],
        ),
      ),
    );
  }
}
