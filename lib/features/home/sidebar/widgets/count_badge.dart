import 'package:flutter/material.dart';

/// Badge showing message count for a conversation
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.selected = false});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final Color bg = selected
        ? cs.onSurface.withOpacity(isDark ? 0.22 : 0.12)
        : cs.onSurface.withOpacity(isDark ? 0.16 : 0.08);
    final Color fg = selected
        ? cs.onSurface.withOpacity(0.95)
        : cs.onSurface.withOpacity(0.75);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      constraints: const BoxConstraints(minHeight: 18, minWidth: 22),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cs.onSurface.withOpacity(isDark ? 0.18 : 0.12),
          width: 0.5,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        count.toString(),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: fg,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
